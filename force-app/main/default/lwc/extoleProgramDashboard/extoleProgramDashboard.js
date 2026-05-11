import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPrograms from '@salesforce/apex/ExtoleProgramDashboardController.getPrograms';
import startDashboardReport from '@salesforce/apex/ExtoleProgramDashboardController.startDashboardReport';
import pollDashboardReport from '@salesforce/apex/ExtoleProgramDashboardController.pollDashboardReport';
import startPromotionsReport from '@salesforce/apex/ExtoleProgramDashboardController.startPromotionsReport';
import pollPromotionsReport from '@salesforce/apex/ExtoleProgramDashboardController.pollPromotionsReport';

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

export default class ExtoleProgramDashboard extends LightningElement {
    @track programs = [];
    @track selectedProgram = null;
    @track selectedPreset = DEFAULT_PRESET;
    @track selectedGranularity = DEFAULT_PERIOD_FOR_PRESET[DEFAULT_PRESET];
    @track dashboard = null;
    @track selectedStepName = null;

    @track promotions = null;
    @track isLoadingPromotions = false;

    @track isLoadingPrograms = false;
    @track isLoadingDashboard = false;
    @track errorMessage = null;

    pollTimer = null;
    pollAttempts = 0;
    currentReportId = null;
    promotionsReportId = null;

    async connectedCallback() {
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
        this.errorMessage = null;
        this.dashboard = null;
        this.promotions = null;
        this.pollAttempts = 0;

        const preset = PRESETS.find(p => p.value === this.selectedPreset) || PRESETS[2];
        try {
            // Kick off both reports in parallel — they share the poll loop
            const [dash, promo] = await Promise.all([
                startDashboardReport({
                    program: this.selectedProgram,
                    days: preset.days,
                    period: this.selectedGranularity
                }),
                startPromotionsReport({
                    program: this.selectedProgram,
                    days: preset.days,
                    period: this.selectedGranularity
                })
            ]);
            this.currentReportId   = dash.reportId;
            this.promotionsReportId = promo.reportId;
            this.startPolling();
        } catch (error) {
            this.isLoadingDashboard = false;
            this.isLoadingPromotions = false;
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

        if (!this.isLoadingDashboard && !this.isLoadingPromotions) {
            this.stopPolling();
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
            .map(p => {
                const values = (p.sparklineValues || []).map(v => typeof v === 'number' ? v : 0);
                const widthPct = maxTotal > 0 ? Math.max(2, Math.round((p.total / maxTotal) * 100)) : 0;
                return {
                    key:         (p.sourceType || '') + ':' + (p.source || ''),
                    displayName: p.displayName || p.source || p.sourceType,
                    sourceType:  p.sourceType,
                    total:       this.formatNumber(p.total || 0),
                    shareRate:   this.formatPromoRate(p.shareRate),
                    sparkPath:   this.buildSparkPath(values),
                    barStyle:    `width: ${widthPct}%;`
                };
            });
    }

    buildSparkPath(values) {
        if (!values || values.length === 0) return '';
        // Same dimensions as the KPI tile sparkline (extoleTile.js) so the
        // visual treatment is identical.
        const W = 200, H = 48;
        const maxV = Math.max(1, ...values);
        const stepX = values.length > 1 ? W / (values.length - 1) : 0;
        return values
            .map((v, i) => {
                const x = i * stepX;
                const y = H - (v / maxV) * H;
                return `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`;
            })
            .join(' ');
    }

    formatPromoRate(v) {
        if (v == null || typeof v !== 'number') return '—';
        return v.toFixed(1) + '%';
    }

    handleRefresh() {
        this.fetchDashboard();
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
            return {
                stepName:    step.stepName,
                displayName: step.displayName || step.stepName,
                totalCount:  this.formatNumber(totalCount),
                rateLabel:   this.formatRate(lastRate, step.rateMetric),
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
