import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import testConnection from '@salesforce/apex/ExtoleController.testConnection';
import getReportTypes from '@salesforce/apex/ExtoleController.getReportTypes';
import saveConfig from '@salesforce/apex/ExtoleController.saveConfig';
import triggerSync from '@salesforce/apex/ExtoleController.triggerSync';

import LABEL_STEP1 from '@salesforce/label/c.Extole_Onboarding_Step1';
import LABEL_STEP2 from '@salesforce/label/c.Extole_Onboarding_Step2';
import LABEL_STEP3 from '@salesforce/label/c.Extole_Onboarding_Step3';
import LABEL_STEP1_DESC from '@salesforce/label/c.Extole_Onboarding_Step1_Desc';
import LABEL_STEP2_DESC from '@salesforce/label/c.Extole_Onboarding_Step2_Desc';
import LABEL_STEP3_DESC from '@salesforce/label/c.Extole_Onboarding_Step3_Desc';
import LABEL_GO_TO_SETUP from '@salesforce/label/c.Extole_Onboarding_GoToSetup';
import LABEL_SYNC_NOW from '@salesforce/label/c.Extole_Settings_SyncNow';
import LABEL_REPORT_COUNT from '@salesforce/label/c.Extole_Connection_ReportCount';

export default class ExtoleOnboarding extends LightningElement {
    @track currentStep = 1;
    @track isTesting = false;
    @track connectionResult = null;
    @track isConnected = false;
    @track isLoadingReportTypes = false;
    @track rawReportTypes = [];
    @track selectedReportTypeId = null;
    @track selectedReportType = null;
    @track isSyncing = false;
    @track syncComplete = false;

    labelStep1 = LABEL_STEP1;
    labelStep2 = LABEL_STEP2;
    labelStep3 = LABEL_STEP3;
    labelStep1Desc = LABEL_STEP1_DESC;
    labelStep2Desc = LABEL_STEP2_DESC;
    labelStep3Desc = LABEL_STEP3_DESC;
    labelGoToSetup = LABEL_GO_TO_SETUP;
    labelSyncNow = LABEL_SYNC_NOW;
    labelReportCount = LABEL_REPORT_COUNT;
    labelTestConnection = 'Test Connection';

    get isNotConnected() { return !this.isConnected; }
    get noReportTypeSelected() { return !this.selectedReportTypeId; }
    get isCurrentStep1() { return this.currentStep === 1; }
    get isCurrentStep2() { return this.currentStep === 2; }
    get isCurrentStep3() { return this.currentStep === 3; }

    get isStep1Done() { return this.currentStep > 1; }
    get isStep2Done() { return this.currentStep > 2; }

    get step1Class() { return this.getStepClass(1); }
    get step2Class() { return this.getStepClass(2); }
    get step3Class() { return this.getStepClass(3); }

    getStepClass(n) {
        if (this.currentStep === n) return 'stepper-item step-current';
        if (this.currentStep > n) return 'stepper-item step-done';
        return 'stepper-item step-future';
    }

    get connectionResultClass() {
        if (!this.connectionResult) return '';
        return this.connectionResult.success ? 'connection-result result-success' : 'connection-result result-error';
    }

    get filteredReportTypes() {
        return this.rawReportTypes
            .filter(rt => {
                const hasJson = rt.formats && rt.formats.includes('JSON');
                return hasJson && ['CONFIGURED', 'SPARK', 'SQL'].includes(rt.type);
            })
            .map(rt => ({
                ...rt,
                isSql: rt.type === 'SQL',
                rowClass: rt.report_type_id === this.selectedReportTypeId
                    ? 'report-row report-row-selected'
                    : 'report-row'
            }));
    }

    async handleTestConnection() {
        this.isTesting = true;
        this.connectionResult = null;
        try {
            const result = await testConnection();
            this.connectionResult = result;
            this.isConnected = result && result.success;
        } catch (error) {
            this.isConnected = false;
            this.connectionResult = {
                success: false,
                errorMessage: (error && error.body && error.body.message) || 'Connection test failed.'
            };
        } finally {
            this.isTesting = false;
        }
    }

    async handleStep1Next() {
        this.currentStep = 2;
        await this.loadReportTypes();
    }

    async loadReportTypes() {
        this.isLoadingReportTypes = true;
        try {
            const raw = await getReportTypes();
            const parsed = JSON.parse(raw);
            this.rawReportTypes = Array.isArray(parsed) ? parsed : (parsed.data || parsed.report_types || []);
        } catch (error) {
            this.rawReportTypes = [];
        } finally {
            this.isLoadingReportTypes = false;
        }
    }

    handleSelectReport(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedReportTypeId = id;
        this.selectedReportType = this.rawReportTypes.find(rt => rt.report_type_id === id);
    }

    async handleStep2Next() {
        if (!this.selectedReportType) return;
        // Save a default config for the selected report type
        try {
            const config = {
                Report_Type__c: this.selectedReportTypeId,
                Report_Name__c: this.selectedReportType.display_name || this.selectedReportType.name,
                Display_Label__c: this.selectedReportType.display_name || '',
                Executor_Type__c: this.selectedReportType.type || '',
                Aggregation__c: 'FIRST_ROW',
                Chart_Type__c: 'Sparkline',
                Date_Range__c: 'Rolling 30',
                Active__c: true,
                Display_Order__c: 1,
                Value_Column__c: this.selectedReportType.preview_columns
                    ? this.selectedReportType.preview_columns[0] || ''
                    : ''
            };
            await saveConfig({ config });
        } catch (error) {
            // Non-fatal — proceed to step 3 anyway
        }
        this.currentStep = 3;
    }

    handleStep2Back() {
        this.currentStep = 1;
    }

    handleStep3Back() {
        this.currentStep = 2;
    }

    async handleRunSync() {
        this.isSyncing = true;
        try {
            await triggerSync();
            this.syncComplete = true;
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Sync failed. Please try again.',
                variant: 'error'
            }));
        } finally {
            this.isSyncing = false;
        }
    }

    handleFinish() {
        this.dispatchEvent(new CustomEvent('onboardingcomplete'));
    }
}
