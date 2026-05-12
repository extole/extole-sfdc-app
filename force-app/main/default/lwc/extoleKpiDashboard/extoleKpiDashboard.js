import { LightningElement, track, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSnapshots from '@salesforce/apex/ExtoleController.getSnapshots';
import getConfigs from '@salesforce/apex/ExtoleController.getConfigs';
import getSettings from '@salesforce/apex/ExtoleController.getSettings';

import LABEL_TITLE from '@salesforce/label/c.Extole_Overview_Title';
import LABEL_NO_DATA_ADMIN from '@salesforce/label/c.Extole_Overview_NoDataAdmin';
import LABEL_NO_DATA_VIEWER from '@salesforce/label/c.Extole_Overview_NoDataViewer';
import LABEL_TOKEN_INVALID from '@salesforce/label/c.Extole_Overview_TokenInvalid';

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

export default class ExtoleKpiDashboard extends NavigationMixin(LightningElement) {
    @track snapshots = [];
    @track configs = [];
    @track settings = null;
    @track isLoading = true;
    @track hasTokenError = false;

    @track palette = DEFAULT_PALETTE;
    @track showPalettePopover = false;

    labelTitle = LABEL_TITLE;
    labelNoDataAdmin = LABEL_NO_DATA_ADMIN;
    labelNoDataViewer = LABEL_NO_DATA_VIEWER;
    labelTokenInvalid = LABEL_TOKEN_INVALID;

    connectedCallback() {
        this.loadPalette();
        this.loadData();
    }

    @api
    refresh() {
        this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        try {
            const [snapshotsResult, configsResult, settingsResult] = await Promise.all([
                getSnapshots(),
                getConfigs(),
                getSettings()
            ]);
            this.snapshots = snapshotsResult || [];
            this.configs = configsResult || [];
            this.settings = settingsResult;
            this.hasTokenError = false;
        } catch (error) {
            const msg = (error && error.body && error.body.message) || '';
            if (msg.includes('401') || msg.toLowerCase().includes('unauthorized') || msg.toLowerCase().includes('credential')) {
                this.hasTokenError = true;
            } else {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: msg || 'Failed to load dashboard data.',
                    variant: 'error'
                }));
            }
        } finally {
            this.isLoading = false;
        }
    }

    get filteredSnapshots() {
        const sorted = this.snapshots
            .slice()
            .sort((a, b) => (a.Display_Order__c || 0) - (b.Display_Order__c || 0));
        if (this.palette !== 'rainbow') {
            return sorted.map(s => ({ ...s, tileStyle: '' }));
        }
        return sorted.map((s, i) => ({
            ...s,
            tileStyle: `--extole-green: ${RAINBOW_COLORS[i % RAINBOW_COLORS.length]};`
        }));
    }

    get showAdminSetup() {
        return !this.isLoading && this.snapshots.length === 0 && this.configs.length === 0;
    }

    get showViewerEmpty() {
        return !this.isLoading && this.snapshots.length === 0 && this.configs.length > 0;
    }

    handleGoToSettings() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Extole_Configure_KPIs' }
        });
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

    get hasData() {
        return !this.isLoading && this.snapshots.length > 0;
    }
}
