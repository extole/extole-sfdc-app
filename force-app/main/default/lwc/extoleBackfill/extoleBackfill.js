import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getWritebackFields  from '@salesforce/apex/ExtoleBackfillController.getWritebackFields';
import getExtoleCampaigns  from '@salesforce/apex/ExtoleBackfillController.getExtoleCampaigns';
import getReports          from '@salesforce/apex/ExtoleBackfillController.getReports';
import previewCount        from '@salesforce/apex/ExtoleBackfillController.previewCount';
import startBackfill       from '@salesforce/apex/ExtoleBackfillController.startBackfill';
import getBackfillLogs     from '@salesforce/apex/ExtoleBackfillController.getBackfillLogs';
import clearBackfillLogs   from '@salesforce/apex/ExtoleBackfillController.clearBackfillLogs';

export default class ExtoleBackfill extends LightningElement {

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

    @track previewCountValue  = null;
    @track isCountingForRun   = false;

    @track isRunning          = false;
    @track showConfirmModal   = false;

    @track logs               = [];
    @track isLoadingLogs      = true;
    @track isClearingLogs     = false;
    @track confirmClearLogs   = false;

    _pollTimer = null;

    get isContact()       { return this.selectedObject === 'Contact'; }
    get isLead()          { return this.selectedObject === 'Lead'; }
    get isDefaultFilter() { return this.audienceType === 'default'; }
    get isDateFilter()    { return this.audienceType === 'date'; }
    get isReportFilter()  { return this.audienceType === 'report'; }
    get hasFieldOptions() { return this.fieldOptions.length > 0; }
    get hasLogs()         { return this.logs && this.logs.length > 0; }

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
        const campaign = this.selectedProgram || 'default';
        const count   = this.previewCountValue !== null
            ? this.previewCountValue.toLocaleString()
            : 'the matching';
        const obj = this.selectedObject === 'Contact' ? 'contacts' : 'leads';
        let audienceClause = '';
        if (this.audienceType === 'date' && this.selectedDate) {
            audienceClause = ` created on or after ${this.selectedDate}`;
        }
        return `You are about to generate "${campaign}" share links and write them to the ${field} field on ${count} ${obj}${audienceClause}. Continue?`;
    }

    connectedCallback() {
        this.loadFields();
        this.loadCampaigns();
        this.loadReports();
        this.loadLogs();
    }

    disconnectedCallback() {
        this._stopPolling();
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

    async loadReports(searchTerm) {
        this.isLoadingReports = true;
        try {
            this.reportOptions = await getReports({ searchTerm: searchTerm || '' }) || [];
        } catch (e) {
            this.reportOptions = [];
        } finally {
            this.isLoadingReports = false;
        }
    }

    async loadLogs() {
        this.isLoadingLogs = true;
        try {
            const result = await getBackfillLogs();
            this.logs = (result || []).map(l => this._mapLog(l));
            if (this.logs.some(l => l.isInProgress)) this._startPolling();
        } catch (e) {
            this.logs = [];
        } finally {
            this.isLoadingLogs = false;
        }
    }

    _mapLog(l) {
        const s = l.Status__c;
        const statusLabel = { IN_PROGRESS: 'In Progress', COMPLETED: 'Completed', COMPLETED_WITH_ERRORS: 'Errors', FAILED: 'Failed' }[s] || s;
        const statusClass = s === 'COMPLETED'             ? 'log-badge-success'
            : s === 'IN_PROGRESS'           ? 'log-badge-skipped'
            : s === 'COMPLETED_WITH_ERRORS' ? 'log-badge-unknown'
            : 'log-badge-failed';
        let errorDetail = '';
        if (l.Error_Detail__c) {
            try {
                const errs = JSON.parse(l.Error_Detail__c);
                if (errs.length > 0) {
                    const first = errs[0].name ? `${errs[0].name}: ${errs[0].error}` : errs[0].error;
                    errorDetail = errs.length > 1 ? `${first} (+${errs.length - 1} more)` : first;
                }
            } catch (e) { /* leave empty */ }
        }
        return {
            ...l,
            statusLabel,
            statusClass,
            isInProgress: s === 'IN_PROGRESS',
            errorDetail,
            detailClass: errorDetail ? 'error-cell' : 'truncated-cell',
            formattedStarted: l.Started_At__c
                ? new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true }).format(new Date(l.Started_At__c))
                : ''
        };
    }

    _startPolling() {
        if (this._pollTimer) return;
        this._pollTimer = setInterval(async () => {
            try {
                const result = await getBackfillLogs();
                this.logs = (result || []).map(l => this._mapLog(l));
                if (!this.logs.some(l => l.isInProgress)) this._stopPolling();
            } catch (e) {
                this._stopPolling();
            }
        }, 3000);
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
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

    handleReportSearch(evt) {
        clearTimeout(this._reportSearchTimer);
        const term = evt.detail.value;
        this._reportSearchTimer = setTimeout(() => {
            this.loadReports(term);
        }, 300);
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
            const selectedOption = this.campaignOptions.find(o => o.value === this.selectedProgram);
            await startBackfill({
                objectType:    this.selectedObject,
                audienceType:  this.audienceType,
                selectedDate:  this.selectedDate,
                reportId:      this.selectedReportId,
                targetField:   this.selectedField,
                programLabel:  this.selectedProgram || '',
                programName:   selectedOption ? selectedOption.label : ''
            });
            await this.loadLogs();
        } catch (e) {
            console.error('Backfill start failed', e);
        } finally {
            this.isRunning = false;
        }
    }

    handleRefreshLogs() {
        this.loadLogs();
    }

    handleCopyLogMd() {
        const now = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date());
        const headers = ['Started', 'Object', 'Audience', 'Program', 'Field', 'Status', 'Total', 'Success', 'Errors', 'Details'];
        const rows = this.logs.map(l => [
            l.formattedStarted || '', l.Object_Type__c || '', l.Audience_Type__c || '',
            l.Program_Label__c || '', l.Target_Field__c || '', l.Status__c || '',
            l.Total_Count__c != null ? l.Total_Count__c : '',
            l.Success_Count__c != null ? l.Success_Count__c : '',
            l.Error_Count__c != null ? l.Error_Count__c : '',
            l.errorDetail || ''
        ]);
        this._copyToClipboard(this._buildMarkdownTable(`Share Link Backfill Log — ${now}`, headers, rows));
    }

    handleClearLogs()          { this.confirmClearLogs = true; }
    handleCancelClearLogs()    { this.confirmClearLogs = false; }

    async handleConfirmClearLogs() {
        this.confirmClearLogs = false;
        this.isClearingLogs   = true;
        try {
            await clearBackfillLogs();
            this.logs = [];
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: 'Failed to clear logs.', variant: 'error' }));
        } finally {
            this.isClearingLogs = false;
        }
    }

    _copyToClipboard(text) {
        const el = document.createElement('textarea');
        el.value = text;
        el.style.position = 'fixed';
        el.style.opacity = '0';
        document.body.appendChild(el);
        el.focus();
        el.select();
        try {
            document.execCommand('copy');
            this.dispatchEvent(new ShowToastEvent({ title: 'Copied', message: 'Log copied to clipboard.', variant: 'success' }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: 'Could not copy to clipboard.', variant: 'error' }));
        } finally {
            document.body.removeChild(el);
        }
    }

    _buildMarkdownTable(title, headers, rows) {
        const esc = s => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ');
        const header  = `| ${headers.map(esc).join(' | ')} |`;
        const divider = `| ${headers.map(() => '---').join(' | ')} |`;
        const body    = rows.map(r => `| ${r.map(esc).join(' | ')} |`).join('\n');
        return `## ${title}\n\n${header}\n${divider}\n${body || '| (no records) |'}`;
    }
}
