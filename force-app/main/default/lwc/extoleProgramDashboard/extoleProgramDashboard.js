import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPrograms from '@salesforce/apex/ExtoleProgramDashboardController.getPrograms';
import startDashboardReport from '@salesforce/apex/ExtoleProgramDashboardController.startDashboardReport';
import pollDashboardReport from '@salesforce/apex/ExtoleProgramDashboardController.pollDashboardReport';
import startPromotionsReport from '@salesforce/apex/ExtoleProgramDashboardController.startPromotionsReport';
import pollPromotionsReport from '@salesforce/apex/ExtoleProgramDashboardController.pollPromotionsReport';
import startChannelsReport from '@salesforce/apex/ExtoleProgramDashboardController.startChannelsReport';
import pollChannelsReport from '@salesforce/apex/ExtoleProgramDashboardController.pollChannelsReport';
import getCurrentUserTimezone from '@salesforce/apex/ExtoleController.getCurrentUserTimezone';

const POLL_INTERVAL_MS = 1500;
const MAX_POLL_ATTEMPTS = 60; // 90 seconds total

const PRESETS = [
    { label: 'Last 7 days',   value: '7d',   days: 7   },
    { label: 'Last 30 days',  value: '30d',  days: 30  },
    { label: 'Last 90 days',  value: '90d',  days: 90  },
    { label: 'Last 6 months', value: '6mo',  days: 180 },
    { label: 'Last year',     value: '1y',   days: 365 }
];
const DEFAULT_PRESET = '90d';

// Sensible default granularity per period range.
const DEFAULT_PERIOD_FOR_PRESET = {
    '7d':  'DAY',
    '30d': 'DAY',
    '90d': 'WEEK',
    '6mo': 'WEEK',
    '1y':  'MONTH'
};

const GRANULARITIES = [
    { label: 'Daily',   value: 'DAY'   },
    { label: 'Weekly',  value: 'WEEK'  },
    { label: 'Monthly', value: 'MONTH' }
];

const PALETTE_STORAGE_KEY = 'extole-dashboard-palette';
const DEFAULT_PALETTE = 'green';
const PALETTE_OPTIONS = [
    { value: 'green',   label: 'Green',   cssClass: 'palette-swatch palette-swatch-green'   },
    { value: 'blue',    label: 'Blue',    cssClass: 'palette-swatch palette-swatch-blue'    },
    { value: 'purple',  label: 'Purple',  cssClass: 'palette-swatch palette-swatch-purple'  },
    { value: 'orange',  label: 'Orange',  cssClass: 'palette-swatch palette-swatch-orange'  },
    { value: 'pink',    label: 'Pink',    cssClass: 'palette-swatch palette-swatch-pink'    },
    { value: 'rainbow', label: 'Rainbow', cssClass: 'palette-swatch palette-swatch-rainbow' }
];
const RAINBOW_COLORS = ['#EF4444', '#F97316', '#EAB308', '#1D9E75', '#2563EB', '#8B5CF6'];
const PALETTE_PRIMARY = {
    green:  '#1D9E75',
    blue:   '#2563EB',
    purple: '#8B5CF6',
    orange: '#F97316',
    pink:   '#E94560'
};
const PALETTE_FILL_RGBA = {
    green:  'rgba(29, 158, 117, 0.12)',
    blue:   'rgba(37, 99, 235, 0.12)',
    purple: 'rgba(139, 92, 246, 0.12)',
    orange: 'rgba(249, 115, 22, 0.12)',
    pink:   'rgba(233, 69, 96, 0.12)'
};

export default class ExtoleProgramDashboard extends LightningElement {
    @track programs = [];
    @track selectedProgram = null;
    @track selectedPreset = DEFAULT_PRESET;
    @track selectedGranularity = DEFAULT_PERIOD_FOR_PRESET[DEFAULT_PRESET];
    @track dashboard = null;
    @track selectedStepName = null;

    @track promotions = null;
    @track isLoadingPromotions = false;

    @track channels = null;
    @track isLoadingChannels = false;

    @track isLoadingPrograms = false;
    @track isLoadingDashboard = false;
    @track errorMessage = null;

    pollTimer = null;
    pollAttempts = 0;
    currentReportId = null;
    promotionsReportId = null;
    channelsReportId = null;

    @track palette = DEFAULT_PALETTE;
    @track showPalettePopover = false;

    @track lastUpdatedAt = null;
    userTimezone = null;

    async connectedCallback() {
        this.loadPalette();
        try {
            this.userTimezone = await getCurrentUserTimezone();
        } catch (e) {
            // Fall back to browser tz if the Apex call fails
        }
        await this.loadPrograms();
        if (this.selectedProgram) {
            this.fetchDashboard();
        }
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    async loadPrograms() {
        this.isLoadingPrograms = true;
        try {
            const result = await getPrograms();
            const filtered = (result || []).filter(p =>
                p.state === 'LIVE' || p.state === 'ACTIVE'
            );
            this.programs = filtered.length ? filtered : (result || []);
            if (this.programs.length > 0) {
                const sorted = [...this.programs].sort((a, b) =>
                    (a.displayName || '').localeCompare(b.displayName || ''));
                this.selectedProgram = sorted[0].label;
            }
        } catch (error) {
            this.errorMessage = this.errMessage(error, 'Failed to load programs.');
        } finally {
            this.isLoadingPrograms = false;
        }
    }

    async fetchDashboard() {
        if (!this.selectedProgram) return;
        this.stopPolling();
        this.isLoadingDashboard = true;
        this.isLoadingPromotions = true;
        this.isLoadingChannels = true;
        this.errorMessage = null;
        this.dashboard = null;
        this.promotions = null;
        this.channels = null;
        this.pollAttempts = 0;

        const preset = PRESETS.find(p => p.value === this.selectedPreset) || PRESETS[2];
        try {
            // Kick off all three reports in parallel — they share the poll loop
            const [dash, promo, chan] = await Promise.all([
                startDashboardReport({
                    program: this.selectedProgram,
                    days: preset.days,
                    period: this.selectedGranularity
                }),
                startPromotionsReport({
                    program: this.selectedProgram,
                    days: preset.days,
                    period: this.selectedGranularity
                }),
                startChannelsReport({
                    program: this.selectedProgram,
                    days: preset.days
                })
            ]);
            this.currentReportId    = dash.reportId;
            this.promotionsReportId = promo.reportId;
            this.channelsReportId   = chan.reportId;
            this.startPolling();
        } catch (error) {
            this.isLoadingDashboard = false;
            this.isLoadingPromotions = false;
            this.isLoadingChannels = false;
            this.errorMessage = this.errMessage(error, 'Failed to start dashboard reports.');
        }
    }

    startPolling() {
        this.stopPolling();
        this.pollTimer = setInterval(() => this.tick(), POLL_INTERVAL_MS);
    }

    stopPolling() {
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = null;
        }
    }

    async tick() {
        this.pollAttempts += 1;
        if (this.pollAttempts > MAX_POLL_ATTEMPTS) {
            this.stopPolling();
            this.isLoadingDashboard = false;
            this.isLoadingPromotions = false;
            if (!this.dashboard) this.errorMessage = 'Dashboard report timed out.';
            return;
        }

        // Dashboard poll
        if (this.currentReportId && this.isLoadingDashboard) {
            try {
                const r = await pollDashboardReport({ reportId: this.currentReportId });
                if (r.status === 'DONE' || r.status === 'COMPLETED') {
                    this.isLoadingDashboard = false;
                    this.dashboard = r.data;
                    this.selectedStepName = this.firstStepName();
                } else if (r.status === 'FAILED' || r.status === 'CANCELLED') {
                    this.isLoadingDashboard = false;
                    this.errorMessage = 'Dashboard report failed.';
                }
            } catch (e) { /* transient — retry */ }
        }

        // Promotions poll (independent of dashboard)
        if (this.promotionsReportId && this.isLoadingPromotions) {
            try {
                const r = await pollPromotionsReport({ reportId: this.promotionsReportId });
                if (r.status === 'DONE' || r.status === 'COMPLETED') {
                    this.isLoadingPromotions = false;
                    this.promotions = r.data;
                } else if (r.status === 'FAILED' || r.status === 'CANCELLED') {
                    this.isLoadingPromotions = false;
                    // Non-fatal — funnel still useful without promotions section
                }
            } catch (e) { /* transient — retry */ }
        }

        // Channels poll (independent of dashboard)
        if (this.channelsReportId && this.isLoadingChannels) {
            try {
                const r = await pollChannelsReport({ reportId: this.channelsReportId });
                if (r.status === 'DONE' || r.status === 'COMPLETED') {
                    this.isLoadingChannels = false;
                    this.channels = r.data;
                } else if (r.status === 'FAILED' || r.status === 'CANCELLED') {
                    this.isLoadingChannels = false;
                }
            } catch (e) { /* transient — retry */ }
        }

        if (!this.isLoadingDashboard && !this.isLoadingPromotions && !this.isLoadingChannels) {
            this.stopPolling();
            this.lastUpdatedAt = Date.now();
        }
    }

    firstStepName() {
        if (!this.dashboard || !this.dashboard.steps || this.dashboard.steps.length === 0) return null;
        return this.dashboard.steps[0].stepName;
    }

    // ── Event handlers ──────────────────────────────────────────────────────

    handleProgramChange(event) {
        this.selectedProgram = event.detail.value;
        this.fetchDashboard();
    }

    handlePresetChange(event) {
        this.selectedPreset = event.detail.value;
        // Auto-switch granularity to the sensible default for the new range
        const sensibleGranularity = DEFAULT_PERIOD_FOR_PRESET[this.selectedPreset];
        if (sensibleGranularity) this.selectedGranularity = sensibleGranularity;
        this.fetchDashboard();
    }

    handleGranularityChange(event) {
        this.selectedGranularity = event.detail.value;
        this.fetchDashboard();
    }

    handleStepClick(event) {
        const stepName = event.currentTarget.dataset.step;
        if (stepName && stepName !== this.selectedStepName) {
            this.selectedStepName = stepName;
        }
    }

    get showEmptyChartOverlay() {
        return this.chartSeries && this.chartSeries.hasAnyValue === false;
    }

    // ── Promotions section ───────────────────────────────────────────────────

    get hasPromotions() {
        return this.promotions
            && this.promotions.promotions
            && this.promotions.promotions.length > 0;
    }

    get hasAnyPromotionActivity() {
        if (!this.hasPromotions) return false;
        return this.promotions.promotions.some(p => (p.total || 0) > 0);
    }

    get promotionRows() {
        if (!this.hasPromotions) return [];
        const active = this.promotions.promotions.filter(p => (p.total || 0) > 0);
        if (active.length === 0) return [];
        const maxTotal = Math.max(...active.map(p => p.total || 0));
        return active
            .slice(0, 8)
            .map((p, i) => {
                const values = (p.sparklineValues || []).map(v => typeof v === 'number' ? v : 0);
                const widthPct = maxTotal > 0 ? Math.max(2, Math.round((p.total / maxTotal) * 100)) : 0;
                const rowColor = this.rainbowColorFor(i);
                const barStyle = rowColor
                    ? `width: ${widthPct}%; background: ${this.toRgba(rowColor, 0.20)}; border-left-color: ${rowColor};`
                    : `width: ${widthPct}%;`;
                const sparkStyle = rowColor ? `stroke: ${rowColor};` : '';
                return {
                    key:         (p.sourceType || '') + ':' + (p.source || ''),
                    displayName: p.displayName || p.source || p.sourceType,
                    sourceType:  p.sourceType,
                    total:       this.formatNumber(p.total || 0),
                    shareRate:   this.formatPromoRate(p.shareRate),
                    sparkPath:   this.buildSparkPath(values),
                    barStyle,
                    sparkStyle
                };
            });
    }

    buildSparkPath(values) {
        if (!values || values.length < 2) return '';
        const W = 200, H = 48;
        const min = Math.min(...values);
        const max = Math.max(...values);
        const range = (max - min) || 1;
        const pad = H * 0.1;
        const innerH = H - pad * 2;
        const pts = values.map((v, i) => {
            const x = (i / (values.length - 1)) * W;
            const y = pad + innerH - ((v - min) / range) * innerH;
            return `${x.toFixed(1)},${y.toFixed(1)}`;
        });
        return 'M ' + pts.join(' L ');
    }

    formatPromoRate(v) {
        if (v == null || typeof v !== 'number') return '—';
        return v.toFixed(1) + '%';
    }

    // ── Channels section ─────────────────────────────────────────────────────

    get hasChannels() {
        return this.channels && this.channels.channels && this.channels.channels.length > 0;
    }

    get sharesLabel() {
        return (this.channels && this.channels.sharesLabel) || 'Shares';
    }

    get shareCtrLabel() {
        return (this.channels && this.channels.shareCtrLabel) || 'Share CTR';
    }

    get conversionLabel() {
        return (this.channels && this.channels.conversionLabel) || 'Conversions';
    }

    get conversionRateLabel() {
        return (this.channels && this.channels.conversionRateLabel) || 'Conversion Rate';
    }

    get channelRows() {
        if (!this.hasChannels) return [];
        const active = this.channels.channels
            .filter(c => (Number(c.shares) || 0) > 0 || (Number(c.accountOpenings) || 0) > 0)
            .slice(0, 8);
        if (active.length === 0) return [];
        const maxValue = Math.max(
            ...active.map(c => Number(c.shares) || 0),
            ...active.map(c => Number(c.accountOpenings) || 0),
            1
        );
        return active.map((c, i) => {
            const sharesV = Number(c.shares) || 0;
            const opensV  = Number(c.accountOpenings) || 0;
            const sharePct = Math.max(2, Math.round((sharesV / maxValue) * 100));
            const openPct  = Math.max(2, Math.round((opensV  / maxValue) * 100));
            const rowColor = this.rainbowColorFor(i);
            const shareBarStyle = rowColor
                ? `width: ${sharePct}%; background: ${rowColor};`
                : `width: ${sharePct}%;`;
            const openBarStyle  = rowColor
                ? `width: ${openPct}%; background: ${this.toRgba(rowColor, 0.45)};`
                : `width: ${openPct}%;`;
            const ctr = this.splitRate(c.shareClickThrough, 'x');
            const rate = this.splitRate(c.conversionRate, '%');
            return {
                key:                  c.channel,
                displayName:          c.displayName || c.channel,
                shares:               this.formatNumber(sharesV),
                accountOpenings:      this.formatNumber(opensV),
                shareCtrValue:        ctr.value,
                shareCtrSuffix:       ctr.suffix,
                conversionRateValue:  rate.value,
                conversionRateSuffix: rate.suffix,
                shareBarStyle,
                openBarStyle
            };
        });
    }

    splitRate(v, suffix) {
        if (v == null || typeof v !== 'number') return { value: '—', suffix: '' };
        return { value: v.toFixed(2), suffix };
    }

    formatChannelRate(v, suffix) {
        if (v == null || typeof v !== 'number') return '—';
        if (suffix === 'X') return v.toFixed(2) + 'X';
        return v.toFixed(2) + '%';
    }

    handleRefresh() {
        this.fetchDashboard();
    }

    // ── Palette ─────────────────────────────────────────────────────────────

    loadPalette() {
        try {
            const saved = window.localStorage.getItem(PALETTE_STORAGE_KEY);
            if (saved && PALETTE_OPTIONS.some(o => o.value === saved)) {
                this.palette = saved;
            }
        } catch (e) {
            // localStorage may be unavailable; fall back to default
        }
    }

    handleTogglePalettePopover(event) {
        event.stopPropagation();
        this.showPalettePopover = !this.showPalettePopover;
    }

    handleSelectPalette(event) {
        const value = event.currentTarget.dataset.palette;
        if (!value) return;
        this.palette = value;
        this.showPalettePopover = false;
        try {
            window.localStorage.setItem(PALETTE_STORAGE_KEY, value);
        } catch (e) {
            // Non-fatal; preference just won't persist
        }
    }

    get paletteSwatches() {
        return PALETTE_OPTIONS.map(o => ({
            ...o,
            cssClass: o.cssClass + (o.value === this.palette ? ' palette-swatch-selected' : '')
        }));
    }

    get paletteBugClass() {
        const base = 'palette-bug';
        return this.palette === 'rainbow' ? `${base} palette-bug-rainbow` : base;
    }

    get isRainbow() {
        return this.palette === 'rainbow';
    }

    get chartLineStroke() {
        return this.isRainbow
            ? 'url(#chart-rainbow-gradient)'
            : (PALETTE_PRIMARY[this.palette] || '#1D9E75');
    }

    get chartFillColor() {
        return this.isRainbow
            ? 'url(#chart-rainbow-gradient)'
            : (PALETTE_FILL_RGBA[this.palette] || 'rgba(29, 158, 117, 0.12)');
    }

    get chartFillOpacity() {
        return this.isRainbow ? '0.2' : '1';
    }

    get extoleProgramUrl() {
        return this.selectedProgram
            ? `https://my.extole.com/program/#/${this.selectedProgram}`
            : null;
    }

    get hasExtoleProgramUrl() {
        return !!this.extoleProgramUrl;
    }

    get lastUpdatedLabel() {
        if (!this.lastUpdatedAt) return '';
        const opts = { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' };
        if (this.userTimezone) opts.timeZone = this.userTimezone;
        const formatted = new Intl.DateTimeFormat('en-US', opts).format(new Date(this.lastUpdatedAt));
        return `Updated ${formatted}`;
    }

    rainbowColorFor(i) {
        if (!this.isRainbow) return null;
        return RAINBOW_COLORS[i % RAINBOW_COLORS.length];
    }

    rainbowColorAt(t) {
        const colors = RAINBOW_COLORS;
        const scaled = Math.max(0, Math.min(1, t)) * (colors.length - 1);
        const i = Math.floor(scaled);
        const f = scaled - i;
        if (i >= colors.length - 1) return colors[colors.length - 1];
        return this.interpolateHex(colors[i], colors[i + 1], f);
    }

    interpolateHex(a, b, t) {
        const ar = parseInt(a.slice(1, 3), 16);
        const ag = parseInt(a.slice(3, 5), 16);
        const ab = parseInt(a.slice(5, 7), 16);
        const br = parseInt(b.slice(1, 3), 16);
        const bg = parseInt(b.slice(3, 5), 16);
        const bb = parseInt(b.slice(5, 7), 16);
        const r = Math.round(ar + (br - ar) * t);
        const g = Math.round(ag + (bg - ag) * t);
        const bl = Math.round(ab + (bb - ab) * t);
        return `rgb(${r}, ${g}, ${bl})`;
    }

    toRgba(hex, alpha) {
        const h = hex.replace('#', '');
        const r = parseInt(h.substring(0, 2), 16);
        const g = parseInt(h.substring(2, 4), 16);
        const b = parseInt(h.substring(4, 6), 16);
        return `rgba(${r}, ${g}, ${b}, ${alpha})`;
    }

    // ── Computed view state ─────────────────────────────────────────────────

    get programOptions() {
        return [...this.programs]
            .sort((a, b) => (a.displayName || '').localeCompare(b.displayName || ''))
            .map(p => ({ label: p.displayName || p.label, value: p.label }));
    }

    get presetOptions() {
        return PRESETS.map(p => ({ label: p.label, value: p.value }));
    }

    get granularityOptions() {
        return GRANULARITIES;
    }

    get hasMultiplePrograms() { return this.programs && this.programs.length > 1; }
    get hasOneProgram()       { return this.programs && this.programs.length === 1; }
    get hasNoPrograms()       { return !this.programs || this.programs.length === 0; }

    get selectedProgramLabel() {
        const p = this.programs.find(p => p.label === this.selectedProgram);
        return p ? (p.displayName || p.label) : '';
    }

    get hasDashboardData() {
        return this.dashboard && this.dashboard.steps && this.dashboard.steps.length > 0;
    }

    get funnelStages() {
        if (!this.hasDashboardData) return [];
        const periods = this.dashboard.periods || [];
        return this.dashboard.steps.map(step => {
            const graphValues = (step.graphMetric && step.graphMetric.values) || [];
            const rateValues  = (step.rateMetric  && step.rateMetric.values)  || [];
            const totalCount = graphValues.reduce((acc, v) =>
                acc + (typeof v === 'number' ? v : 0), 0);
            const lastRate = rateValues.length > 0 ? rateValues[rateValues.length - 1] : null;
            const split = this.splitFunnelRate(lastRate, step.rateMetric);
            return {
                stepName:    step.stepName,
                displayName: step.displayName || step.stepName,
                totalCount:  this.formatNumber(totalCount),
                rateValue:   split.value,
                rateSuffix:  split.suffix,
                isSelected:  step.stepName === this.selectedStepName,
                stageClass:  step.stepName === this.selectedStepName
                    ? 'funnel-stage funnel-stage-selected'
                    : 'funnel-stage',
                periodCount: periods.length
            };
        });
    }

    get selectedStep() {
        if (!this.hasDashboardData || !this.selectedStepName) return null;
        return this.dashboard.steps.find(s => s.stepName === this.selectedStepName);
    }

    get chartSeries() {
        const step = this.selectedStep;
        if (!step || !step.graphMetric || !step.graphMetric.values) return null;
        const values = step.graphMetric.values.map(v => typeof v === 'number' ? v : 0);
        if (values.length === 0) return null;

        // The SVG uses a 0-200 viewBox in both dimensions for the plot area only.
        // Y-axis labels live OUTSIDE the SVG (rendered in HTML) so they don't get
        // stretched by preserveAspectRatio="none". The HTML column sits to the
        // left of the SVG and is sized in CSS pixels.
        const W = 800, H = 200;
        const PT = 6, PB = 18; // top/bottom padding for plot area
        const innerH = H - PT - PB;

        const rawMax = Math.max(...values);
        const hasAnyValue = rawMax > 0;
        const maxV = Math.max(1, rawMax);
        const stepX = values.length > 1 ? W / (values.length - 1) : 0;
        const points = values.map((v, i) => {
            const x = i * stepX;
            const y = PT + innerH - (v / maxV) * innerH;
            return { x, y };
        });
        const pathD = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x},${p.y}`).join(' ');
        const fillD = pathD + ` L${points[points.length-1].x},${PT+innerH} L${points[0].x},${PT+innerH} Z`;

        // Rainbow mode: render N-1 segments for both the line and the fill,
        // each with a smooth-interpolated rainbow color. Avoids SVG gradients
        // (which LWC/shadow-DOM-url-refs don't play nice with).
        const baseY = PT + innerH;
        const segCount = Math.max(points.length - 1, 1);
        const lineSegments = [];
        const fillSegments = [];
        for (let i = 0; i < points.length - 1; i++) {
            const a = points[i], b = points[i + 1];
            const t = segCount > 1 ? i / (segCount - 1) : 0;
            const color = this.rainbowColorAt(t);
            lineSegments.push({
                key: 'line-' + i,
                d: `M${a.x},${a.y} L${b.x},${b.y}`,
                stroke: color
            });
            fillSegments.push({
                key: 'fill-' + i,
                d: `M${a.x},${a.y} L${b.x},${b.y} L${b.x},${baseY} L${a.x},${baseY} Z`,
                fill: color
            });
        }

        // Y-axis labels rendered in HTML (top-to-bottom order).
        const yLabels = [
            { label: this.formatNumber(maxV) },
            { label: '0' }
        ];
        // Gridlines stay in SVG but use non-scaling-stroke so they don't distort.
        const yGridLines = [
            { y: PT },                  // top (max)
            { y: PT + innerH }          // bottom (0)
        ];

        // X-axis labels — sample evenly so we get ~5-6 labels regardless of how
        // many data points there are. Labels rendered in HTML below the SVG.
        const periods = this.dashboard.periods || [];
        const xLabels = this.buildXLabels(periods);

        return {
            width: W, height: H,
            pathD, fillD,
            lineSegments,
            fillSegments,
            yLabels,
            yGridLines,
            xLabels,
            hasAnyValue,
            metricName: step.graphMetric.name,
            unit: step.graphMetric.unit
        };
    }

    /**
     * Pick evenly-spaced periods to label using an integer step size.
     * Always starts at index 0; subsequent labels at constant intervals.
     * The very last data point may not get its own label so spacing stays uniform.
     */
    buildXLabels(periods) {
        if (!periods || periods.length === 0) return [];
        const granularity = this.selectedGranularity;
        const formatter = (per) => this.formatPeriodForGranularity(per, granularity);

        const n = periods.length;
        if (n === 1) {
            return [{ leftPct: 0, label: formatter(periods[0]), style: 'left: 0%;' }];
        }
        const targetMax = 6;
        // Integer step size so gaps between labels are uniform.
        const step = n <= targetMax ? 1 : Math.max(1, Math.round((n - 1) / (targetMax - 1)));

        const result = [];
        for (let idx = 0; idx < n; idx += step) {
            const leftPct = (idx / (n - 1)) * 100;
            let style;
            if (leftPct < 1)       style = 'left: 0%;';
            else if (leftPct > 99) style = 'right: 0%;';
            else                   style = `left: ${leftPct}%; transform: translateX(-50%);`;
            result.push({ leftPct, label: formatter(periods[idx]), style });
        }
        return result;
    }

    formatPeriodForGranularity(period, granularity) {
        if (!period || !period.start) return '';
        const d = new Date(period.start);
        if (granularity === 'MONTH') {
            return d.toLocaleString('en-US', { month: 'short', year: '2-digit' });
        }
        // DAY and WEEK both display as "Mon DD"
        return d.toLocaleString('en-US', { month: 'short', day: 'numeric' });
    }

    // ── Formatting helpers ───────────────────────────────────────────────────

    formatNumber(n) {
        if (n == null) return '—';
        if (typeof n !== 'number') return String(n);
        if (n >= 1_000_000) return (n / 1_000_000).toFixed(1).replace(/\.0$/, '') + 'M';
        if (n >= 1_000)     return (n / 1_000).toFixed(1).replace(/\.0$/, '') + 'k';
        return String(n);
    }

    formatRate(v, metric) {
        if (v == null || typeof v !== 'number') return '—';
        if (metric && metric.unit === '%')   return v.toFixed(1) + '%';
        if (metric && metric.unit === 'X')   return v.toFixed(2) + '×';
        return v.toFixed(1);
    }

    splitFunnelRate(v, metric) {
        if (v == null || typeof v !== 'number') return { value: '—', suffix: '' };
        if (metric && metric.unit === '%') return { value: v.toFixed(1), suffix: '%' };
        if (metric && metric.unit === 'X') return { value: v.toFixed(2), suffix: '×' };
        return { value: v.toFixed(1), suffix: '' };
    }

    formatPeriodLabel(period) {
        if (!period || !period.start) return '';
        const d = new Date(period.start);
        const month = d.toLocaleString('en-US', { month: 'short' });
        return `${month} ${d.getDate()}`;
    }

    errMessage(error, fallback) {
        return (error && error.body && error.body.message) || fallback;
    }
}
