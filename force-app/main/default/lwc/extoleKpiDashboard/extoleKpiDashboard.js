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

export default class ExtoleKpiDashboard extends NavigationMixin(LightningElement) {
    @track snapshots = [];
    @track configs = [];
    @track settings = null;
    @track isLoading = true;
    @track hasTokenError = false;

    labelTitle = LABEL_TITLE;
    labelNoDataAdmin = LABEL_NO_DATA_ADMIN;
    labelNoDataViewer = LABEL_NO_DATA_VIEWER;
    labelTokenInvalid = LABEL_TOKEN_INVALID;

    connectedCallback() {
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
        return this.snapshots
            .slice()
            .sort((a, b) => (a.Display_Order__c || 0) - (b.Display_Order__c || 0));
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
}
