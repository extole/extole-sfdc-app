import { LightningElement, api } from 'lwc';
import LABEL_VIEW_IN_EXTOLE from '@salesforce/label/c.Extole_Tile_ViewInExtole';
import LABEL_ORPHANED from '@salesforce/label/c.Extole_Tile_Orphaned';
import LABEL_SYNC_PENDING from '@salesforce/label/c.Extole_Tile_SyncPending';
import LABEL_SYNC_FAILED from '@salesforce/label/c.Extole_Tile_SyncFailed';
import LABEL_AS_OF from '@salesforce/label/c.Extole_AsOf';

const CHART_WIDTH = 200;
const CHART_HEIGHT = 48;

export default class ExtoleTile extends LightningElement {
    @api snapshot;

    labelViewInExtole = LABEL_VIEW_IN_EXTOLE;
    labelOrphaned = LABEL_ORPHANED;
    labelSyncPending = LABEL_SYNC_PENDING;
    labelSyncFailed = LABEL_SYNC_FAILED;
    labelAsOf = LABEL_AS_OF;

    get tileClass() {
        const base = 'extole-tile';
        if (this.isOrphaned) return `${base} tile-orphaned`;
        return base;
    }

    get isOrphaned() {
        return this.snapshot && this.snapshot.Config_Status__c === 'ORPHANED';
    }

    get isPending() {
        return this.snapshot && !this.snapshot.Value__c && !this.isOrphaned;
    }

    get displayLabel() {
        if (!this.snapshot) return '';
        const label = this.snapshot.Display_Label__c || this.snapshot.Report_Name__c || '';
        return label.length > 120 ? label.substring(0, 117) + '...' : label;
    }

    get formattedValue() {
        if (!this.snapshot || this.snapshot.Value__c == null) return '—';
        const val = parseFloat(this.snapshot.Value__c);
        if (isNaN(val)) return this.snapshot.Value__c;
        return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(val);
    }

    get hasTrend() {
        return this.snapshot &&
            this.snapshot.Prior_Period_Value__c != null &&
            this.snapshot.Value__c != null;
    }

    get trendValue() {
        if (!this.hasTrend) return 0;
        const current = parseFloat(this.snapshot.Value__c) || 0;
        const prior = parseFloat(this.snapshot.Prior_Period_Value__c) || 0;
        if (prior === 0) return 0;
        return ((current - prior) / Math.abs(prior)) * 100;
    }

    get trendArrow() {
        return this.trendValue >= 0 ? '↑' : '↓';
    }

    get trendText() {
        const pct = Math.abs(Math.round(this.trendValue));
        const range = this.snapshot.Date_Range__c || '';
        return `${pct}% vs prior ${range}`;
    }

    get trendClass() {
        return this.trendValue >= 0 ? 'tile-trend trend-up' : 'tile-trend trend-down';
    }

    get chartType() {
        return this.snapshot ? (this.snapshot.Chart_Type__c || 'None') : 'None';
    }

    get hasChart() {
        return this.chartType === 'Sparkline' || this.chartType === 'Bar';
    }

    get isSparkline() {
        return this.chartType === 'Sparkline';
    }

    get isBar() {
        return this.chartType === 'Bar';
    }

    get svgViewBox() {
        return `0 0 ${CHART_WIDTH} ${CHART_HEIGHT}`;
    }

    get gradientId() {
        return `grad-${this.snapshot ? this.snapshot.Id || 'tile' : 'tile'}`;
    }

    get gradientFill() {
        return `url(#${this.gradientId})`;
    }

    get timeSeriesData() {
        if (!this.snapshot || !this.snapshot.Time_Series_JSON__c) return [];
        try {
            return JSON.parse(this.snapshot.Time_Series_JSON__c);
        } catch (e) {
            return [];
        }
    }

    get sparklinePath() {
        return this.computeSparklinePath(this.timeSeriesData, CHART_WIDTH, CHART_HEIGHT);
    }

    get sparklineFillPath() {
        const line = this.sparklinePath;
        if (!line) return '';
        return `${line} L ${CHART_WIDTH},${CHART_HEIGHT} L 0,${CHART_HEIGHT} Z`;
    }

    get barRects() {
        const data = this.timeSeriesData;
        if (!data || data.length === 0) return [];
        const vals = data.map(d => parseFloat(d.value) || 0);
        const maxVal = Math.max(...vals) || 1;
        const barWidth = Math.floor(CHART_WIDTH / vals.length) - 2;
        const lastIdx = vals.length - 1;
        return vals.map((v, i) => {
            const barH = Math.round((v / maxVal) * CHART_HEIGHT);
            return {
                key: `bar-${i}`,
                x: i * (barWidth + 2),
                y: CHART_HEIGHT - barH,
                width: barWidth,
                height: barH,
                fill: '#1D9E75',
                opacity: i === lastIdx ? '1' : '0.25'
            };
        });
    }

    get isStale() {
        if (!this.snapshot || !this.snapshot.Next_Expected_Sync__c) return false;
        return new Date(this.snapshot.Next_Expected_Sync__c) < new Date();
    }

    get asOfText() {
        if (!this.snapshot || !this.snapshot.As_Of_Date__c) return '';
        return `${LABEL_AS_OF} ${this.snapshot.As_Of_Date__c}`;
    }

    get asOfClass() {
        return this.isStale ? 'footer-date footer-stale' : 'footer-date';
    }

    get hasSyncFailed() {
        return this.snapshot && this.snapshot.Config_Status__c === 'FAILED';
    }

    get syncFailedText() {
        if (!this.snapshot) return '';
        const dateStr = this.snapshot.As_Of_Date__c || '';
        return `${LABEL_SYNC_FAILED} ${dateStr}`.trim();
    }

    get hasViewUrl() {
        return this.snapshot && !!this.snapshot.View_URL__c;
    }

    computeSparklinePath(dataPoints, width, height) {
        if (!dataPoints || dataPoints.length < 2) return '';
        const vals = dataPoints.map(d => parseFloat(d.value) || 0);
        const min = Math.min(...vals);
        const max = Math.max(...vals);
        const range = max - min || 1;
        const pts = vals.map((v, i) => {
            const x = Math.round((i / (vals.length - 1)) * width);
            const y = Math.round(height - ((v - min) / range) * height);
            return `${x},${y}`;
        });
        return 'M ' + pts.join(' L ');
    }
}
