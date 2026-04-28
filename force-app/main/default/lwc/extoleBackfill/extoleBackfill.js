import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getWritebackFields  from '@salesforce/apex/ExtoleBackfillController.getWritebackFields';
import getExtoleCampaigns  from '@salesforce/apex/ExtoleBackfillController.getExtoleCampaigns';
import getReports          from '@salesforce/apex/ExtoleBackfillController.getReports';
import previewCount        from '@salesforce/apex/ExtoleBackfillController.previewCount';
import startBackfill       from '@salesforce/apex/ExtoleBackfillController.startBackfill';
import getLastBackfillRun  from '@salesforce/apex/ExtoleBackfillController.getLastBackfillRun';

export default class ExtoleBackfill extends NavigationMixin(LightningElement) {

    @track selectedObject    = 'Contact';
    @track audienceType      = 'default';
    @track selectedDate      = null;
    @track selectedReportId  = null;
    @track selectedField     = null;
    @track selectedProgram   = null;

    @track fieldOptions      = [];
    @track campaignOptions   = [];
    @track reportOptions     = [];
    @track isLoadingFields   = false;
    @track isLoadingCampaigns = false;
    @track isLoadingReports  = false;

    @track previewCountValue = null;
    @track isCountingForRun  = false;

    @track isRunning         = false;
    @track showConfirmModal  = false;

    @track lastRun           = null;
    @track isLoadingLastRun  = true;
    @track showErrorDetail   = false;

    get isContact()       { return this.selectedObject === 'Contact'; }
    get isLead()          { return this.selectedObject === 'Lead'; }
    get isDefaultFilter() { return this.audienceType === 'default'; }
    get isDateFilter()    { return this.audienceType === 'date'; }
    get isReportFilter()  { return this.audienceType === 'report'; }
    get hasFieldOptions() { return this.fieldOptions.length > 0; }

    get campaignOptionsWithNone() {
        return [{ label: 'None', value: '' }, ...this.campaignOptions];
    }

    get shareLinkFieldLabel() {
        return `${this.selectedObject} field`;
    }

    get defaultFilterDescription() {
        return this.selectedObject === 'Contact'
            ? 'Contacts with an email address on any Closed Won opportunity'
            : 'Unconverted leads with an email address';
    }

    get dateFilterDescription() {
        const obj = this.selectedObject === 'Contact' ? 'contacts' : 'leads';
        return `All ${obj} with an email address created on or after a selected date`;
    }

    get isRunDisabled() {
        if (!this.selectedField || this.isRunning || this.isCountingForRun) return true;
        if (this.audienceType === 'report' && !this.selectedReportId) return true;
        if (this.audienceType === 'date'   && !this.selectedDate)     return true;
        return false;
    }

    get confirmMessage() {
        const field   = this.selectedField  || '';
        const program = this.selectedProgram || 'default';
        const count   = this.previewCountValue !== null
            ? this.previewCountValue.toLocaleString()
            : 'the matching';
        const obj = this.selectedObject === 'Contact' ? 'contacts' : 'leads';
        let audienceClause = '';
        if (this.audienceType === 'date' && this.selectedDate) {
            audienceClause = ` created on or after ${this.selectedDate}`;
        }
        return `You are about to generate "${program}" share links and write them to the ${field} field on ${count} ${obj}${audienceClause}. Continue?`;
    }

    get lastRunTimestamp() {
        if (!this.lastRun || !this.lastRun.Started_At__c) return '';
        return new Date(this.lastRun.Started_At__c).toLocaleString();
    }

    get lastRunStatusClass() {
        if (!this.lastRun) return '';
        const s = this.lastRun.Status__c;
        if (s === 'COMPLETED')             return 'status-badge status-success';
        if (s === 'IN_PROGRESS')           return 'status-badge status-progress';
        if (s === 'COMPLETED_WITH_ERRORS') return 'status-badge status-warn';
        return 'status-badge status-error';
    }

    get lastRunHasErrors() {
        return this.lastRun && this.lastRun.Error_Count__c > 0;
    }

    get parsedErrors() {
        if (!this.lastRun || !this.lastRun.Error_Detail__c) return [];
        try { return JSON.parse(this.lastRun.Error_Detail__c); }
        catch (e) { return []; }
    }

    connectedCallback() {
        this.loadFields();
        this.loadCampaigns();
        this.loadReports();
        this.loadLastRun();
    }

    async loadFields() {
        this.isLoadingFields = true;
        try {
            const result = await getWritebackFields({ objectType: this.selectedObject });
            this.fieldOptions  = result || [];
            this.selectedField = null;
        } catch (e) {
            this.fieldOptions = [];
        } finally {
            this.isLoadingFields = false;
        }
    }

    async loadCampaigns() {
        this.isLoadingCampaigns = true;
        try {
            this.campaignOptions = await getExtoleCampaigns() || [];
        } catch (e) {
            this.campaignOptions = [];
        } finally {
            this.isLoadingCampaigns = false;
        }
    }

    async loadReports() {
        this.isLoadingReports = true;
        try {
            this.reportOptions = await getReports() || [];
        } catch (e) {
            this.reportOptions = [];
        } finally {
            this.isLoadingReports = false;
        }
    }

    async loadLastRun() {
        this.isLoadingLastRun = true;
        try {
            this.lastRun = await getLastBackfillRun();
        } catch (e) {
            this.lastRun = null;
        } finally {
            this.isLoadingLastRun = false;
        }
    }

    handleObjectRadioChange(evt) {
        this.selectedObject = evt.target.value;
        this.loadFields();
    }

    handleAudienceRadioChange(evt) {
        this.audienceType = evt.target.value;
    }

    handleDateChange(evt) {
        this.selectedDate = evt.target.value;
    }

    handleReportChange(evt) {
        this.selectedReportId = evt.detail.value;
    }

    handleFieldChange(evt) {
        this.selectedField = evt.detail.value;
    }

    handleProgramChange(evt) {
        this.selectedProgram = evt.detail.value || null;
    }

    handleRunClick() {
        this._countAndConfirm();
    }

    async _countAndConfirm() {
        if (this.audienceType !== 'report') {
            this.isCountingForRun = true;
            try {
                this.previewCountValue = await previewCount({
                    objectType:   this.selectedObject,
                    audienceType: this.audienceType,
                    selectedDate: this.selectedDate,
                    reportId:     this.selectedReportId
                });
            } catch (e) {
                this.previewCountValue = null;
            } finally {
                this.isCountingForRun = false;
            }
        } else {
            this.previewCountValue = null;
        }
        this.showConfirmModal = true;
    }

    handleCancel() {
        this.showConfirmModal = false;
    }

    async handleConfirm() {
        this.showConfirmModal = false;
        this.isRunning        = true;
        try {
            await startBackfill({
                objectType:    this.selectedObject,
                audienceType:  this.audienceType,
                selectedDate:  this.selectedDate,
                reportId:      this.selectedReportId,
                targetField:   this.selectedField,
                programLabel:  this.selectedProgram || ''
            });
            await this.loadLastRun();
        } catch (e) {
            console.error('Backfill start failed', e);
        } finally {
            this.isRunning = false;
        }
    }

    handleViewLogs() {
        this.showErrorDetail = !this.showErrorDetail;
    }
}
