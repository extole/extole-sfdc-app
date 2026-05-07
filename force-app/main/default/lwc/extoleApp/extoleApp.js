import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import EXTOLE_LOGO from '@salesforce/resourceUrl/extole_logo';
import getSettings from '@salesforce/apex/ExtoleController.getSettings';
import getSnapshots from '@salesforce/apex/ExtoleController.getSnapshots';
import getConfigs from '@salesforce/apex/ExtoleController.getConfigs';

import LABEL_TAB_KPI_DASHBOARD from '@salesforce/label/c.Extole_Tab_Overview';
import LABEL_TAB_LIST_VIEW from '@salesforce/label/c.Extole_Tab_ListView';
import LABEL_APP_TITLE from '@salesforce/label/c.Extole_App_Title';

export default class ExtoleApp extends LightningElement {
    @track isLoading = true;
    @track settingsTimestamp = null;
    @track showOnboarding = false;
    @track settings = null;
    @track hasSnapshots = false;
    @track hasConfigs = false;
    @track activeTab = 'overview';
    @track tabsetItems = [{ key: 0 }];

    labelTabKpiDashboard = LABEL_TAB_KPI_DASHBOARD;
    labelTabListView = LABEL_TAB_LIST_VIEW;
    labelAppTitle = LABEL_APP_TITLE;
    extoleLogoUrl = EXTOLE_LOGO;

    connectedCallback() {
        this.initApp();
    }

    async initApp() {
        this.isLoading = true;
        try {
            const [settingsResult, snapshotsResult, configsResult] = await Promise.all([
                getSettings(),
                getSnapshots(),
                getConfigs()
            ]);
            this.settings = settingsResult;
            this.hasSnapshots = snapshotsResult && snapshotsResult.length > 0;
            this.hasConfigs = configsResult && configsResult.length > 0;

            // Show onboarding if no report configs have been set up yet
            this.showOnboarding = !this.hasConfigs;
        } catch (error) {
            // If settings retrieval errors (org not set up), show onboarding
            this.showOnboarding = true;
        } finally {
            this.isLoading = false;
        }
    }

    get showKPIDashboard() {
        return !this.settings || this.settings.Show_KPI_Dashboard__c !== false;
    }

    get showListView() {
        return this.settings && this.settings.Show_List_View__c;
    }

    handleTabChange(event) {
        this.activeTab = event.detail.name;
        if (this.activeTab === 'leads') {
            // Force extoleListView to reload when the tab is activated
            this.settingsTimestamp = Date.now();
        }
    }

    async handleOnboardingComplete() {
        await this.initApp();
        this.showOnboarding = false;
        this.activeTab = 'overview';
    }
}
