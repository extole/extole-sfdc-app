import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSettings from '@salesforce/apex/ExtoleController.getSettings';
import getSnapshots from '@salesforce/apex/ExtoleController.getSnapshots';
import getConfigs from '@salesforce/apex/ExtoleController.getConfigs';

import LABEL_TAB_OVERVIEW from '@salesforce/label/c.Extole_Tab_Overview';
import LABEL_TAB_SETTINGS from '@salesforce/label/c.Extole_Tab_Settings';
import LABEL_TAB_LEAD_ATTRIBUTION from '@salesforce/label/c.Extole_Tab_LeadAttribution';
import LABEL_APP_TITLE from '@salesforce/label/c.Extole_App_Title';

export default class ExtoleApp extends LightningElement {
    @track isLoading = true;
    @track showOnboarding = false;
    @track settings = null;
    @track hasSnapshots = false;
    @track hasConfigs = false;
    @track activeTab = 'overview';

    labelTabOverview = LABEL_TAB_OVERVIEW;
    labelTabSettings = LABEL_TAB_SETTINGS;
    labelTabLeadAttribution = LABEL_TAB_LEAD_ATTRIBUTION;
    labelAppTitle = LABEL_APP_TITLE;

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

            // Show onboarding if no settings AND no snapshots AND no configs
            this.showOnboarding = !this.settings && !this.hasSnapshots && !this.hasConfigs;
        } catch (error) {
            // If settings retrieval errors (org not set up), show onboarding
            this.showOnboarding = true;
        } finally {
            this.isLoading = false;
        }
    }

    get showLeadAttribution() {
        return this.settings && this.settings.Show_Lead_Attribution__c;
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
    }

    handleNavigateToSettings() {
        this.activeTab = 'settings';
    }

    async handleOnboardingComplete() {
        // Reload app state after onboarding
        await this.initApp();
        this.showOnboarding = false;
        this.activeTab = 'overview';
    }
}
