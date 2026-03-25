import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSnapshots from '@salesforce/apex/ExtoleController.getSnapshots';
import getConfigs from '@salesforce/apex/ExtoleController.getConfigs';
import getSettings from '@salesforce/apex/ExtoleController.getSettings';

import LABEL_TITLE from '@salesforce/label/c.Extole_Overview_Title';
import LABEL_NO_PENDING from '@salesforce/label/c.Extole_Overview_NoPending';
import LABEL_NO_DATA_ADMIN from '@salesforce/label/c.Extole_Overview_NoDataAdmin';
import LABEL_NO_DATA_VIEWER from '@salesforce/label/c.Extole_Overview_NoDataViewer';
import LABEL_TOKEN_INVALID from '@salesforce/label/c.Extole_Overview_TokenInvalid';
import LABEL_ROLLING30 from '@salesforce/label/c.Extole_Overview_Rolling30';
import LABEL_ROLLING90 from '@salesforce/label/c.Extole_Overview_Rolling90';
import LABEL_YTD from '@salesforce/label/c.Extole_Overview_YTD';

const RANGE_ROLLING30 = 'Rolling 30';
const RANGE_ROLLING90 = 'Rolling 90';
const RANGE_YTD = 'YTD';

export default class ExtoleProgramOverview extends LightningElement {
    @track selectedRange = RANGE_ROLLING30;
    @track snapshots = [];
    @track configs = [];
    @track settings = null;
    @track isLoading = true;
    @track hasTokenError = false;

    labelTitle = LABEL_TITLE;
    labelNoPending = LABEL_NO_PENDING;
    labelNoDataAdmin = LABEL_NO_DATA_ADMIN;
    labelNoDataViewer = LABEL_NO_DATA_VIEWER;
    labelTokenInvalid = LABEL_TOKEN_INVALID;
    labelRolling30 = LABEL_ROLLING30;
    labelRolling90 = LABEL_ROLLING90;
    labelYTD = LABEL_YTD;

    connectedCallback() {
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
                    message: msg || 'Failed to load overview data.',
                    variant: 'error'
                }));
            }
        } finally {
            this.isLoading = false;
        }
    }

    get filteredSnapshots() {
        return this.snapshots
            .filter(s => s.Date_Range__c === this.selectedRange)
            .sort((a, b) => (a.Display_Order__c || 0) - (b.Display_Order__c || 0));
    }

    get hasNoSnapshotsForRange() {
        return !this.isLoading && this.snapshots.length > 0 && this.filteredSnapshots.length === 0;
    }

    get showAdminSetup() {
        return !this.isLoading && this.snapshots.length === 0 && this.configs.length === 0;
    }

    get showViewerEmpty() {
        return !this.isLoading && this.snapshots.length === 0 && this.configs.length > 0;
    }

    get btnClassRolling30() {
        return this.selectedRange === RANGE_ROLLING30 ? 'range-btn range-btn-active' : 'range-btn';
    }

    get btnClassRolling90() {
        return this.selectedRange === RANGE_ROLLING90 ? 'range-btn range-btn-active' : 'range-btn';
    }

    get btnClassYTD() {
        return this.selectedRange === RANGE_YTD ? 'range-btn range-btn-active' : 'range-btn';
    }

    handleRangeChange(event) {
        this.selectedRange = event.currentTarget.dataset.range;
    }

    handleGoToSettings() {
        this.dispatchEvent(new CustomEvent('navigatetosettings'));
    }
}
