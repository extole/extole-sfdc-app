import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAudienceConfigs from '@salesforce/apex/ExtoleAudienceController.getAudienceConfigs';
import saveAudienceConfig from '@salesforce/apex/ExtoleAudienceController.saveAudienceConfig';
import deleteAudienceConfig from '@salesforce/apex/ExtoleAudienceController.deleteAudienceConfig';
import getAvailableReports from '@salesforce/apex/ExtoleAudienceController.getAvailableReports';
import getReportColumns from '@salesforce/apex/ExtoleAudienceController.getReportColumns';
import syncAudience from '@salesforce/apex/ExtoleAudienceController.syncAudience';
import pollAudienceState from '@salesforce/apex/ExtoleAudienceController.pollAudienceState';
import getAudienceSyncLogs from '@salesforce/apex/ExtoleAudienceController.getAudienceSyncLogs';
import clearAudienceSyncLogs from '@salesforce/apex/ExtoleAudienceController.clearAudienceSyncLogs';
import runSchedulerNow from '@salesforce/apex/ExtoleAudienceController.runSchedulerNow';
import getCurrentUserTimezone from '@salesforce/apex/ExtoleController.getCurrentUserTimezone';

const POLL_INTERVAL_MS = 10000;
const NON_TERMINAL = new Set(['PREPARING', 'BUILDING', 'VALIDATING']);

export default class ExtoleManageAudiences extends LightningElement {
    @track configs = [];
    @track isLoadingConfigs = false;
    @track sortedBy = 'Extole_Audience_Name__c';
    @track sortedDirection = 'asc';

    @track syncLogs = [];
    @track isLoadingLogs = false;
    @track isClearingLogs = false;
    @track confirmClearLogs = false;

    @track isModalOpen = false;
    @track isSaving = false;
    @track modalError = null;
    @track editingConfig = {};
    @track availableReports = [];
    @track isLoadingReports = false;
    @track reportColumns = [];
    @track isLoadingColumns = false;

    pollTimer = null;

    tooltipSectionAudiences = 'Push Salesforce report members into an Extole audience. Each row maps a Salesforce report (identifies people by email) to a named audience in Extole. Members are submitted as a REPLACE — the current report becomes the audience.';

    userTimezone = null;

    async connectedCallback() {
        try {
            this.userTimezone = await getCurrentUserTimezone();
        } catch (e) {
            // Fall back to browser tz if the Apex call fails
        }
        await this.loadConfigs();
        await this.loadSyncLogs();
        this.startPolling();
    }

    formatTimestamp(value, opts) {
        if (!value) return '';
        const merged = { ...opts };
        if (this.userTimezone) merged.timeZone = this.userTimezone;
        return new Intl.DateTimeFormat('en-US', merged).format(new Date(value));
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    startPolling() {
        if (this.pollTimer) return;
        this.pollTimer = setInterval(() => this.pollIfNeeded(), POLL_INTERVAL_MS);
    }

    stopPolling() {
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = null;
        }
    }

    async pollIfNeeded() {
        const active = (this.configs || []).filter(c => NON_TERMINAL.has(c.Last_Operation_State__c));
        if (active.length === 0) return;
        for (const cfg of active) {
            try {
                const fresh = await pollAudienceState({ configKey: cfg.Config_Key__c });
                this.configs = this.configs.map(c =>
                    c.Config_Key__c === cfg.Config_Key__c ? this.decorateConfig(fresh) : c
                );
            } catch (e) {
                // Non-fatal — try again next tick
            }
        }
        // Always reload logs while a sync is active so submission + transition rows surface
        await this.loadSyncLogs();
    }

    async loadConfigs() {
        this.isLoadingConfigs = true;
        try {
            const result = await getAudienceConfigs();
            this.configs = (result || []).map(c => this.decorateConfig(c));
            this.sortConfigs();
        } catch (error) {
            this.showError('Failed to load audience configs.', error);
        } finally {
            this.isLoadingConfigs = false;
        }
    }

    sortConfigs() {
        const field = this.sortedBy;
        const dir = this.sortedDirection === 'asc' ? 1 : -1;
        this.configs = [...this.configs].sort((a, b) => {
            const av = a[field] ?? '';
            const bv = b[field] ?? '';
            return av < bv ? -dir : av > bv ? dir : 0;
        });
    }

    handleSortColumn(event) {
        const field = event.currentTarget.dataset.field;
        if (this.sortedBy === field) {
            this.sortedDirection = this.sortedDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortedBy = field;
            this.sortedDirection = 'asc';
        }
        this.sortConfigs();
    }

    getSortIcon(field) {
        if (this.sortedBy !== field) return '';
        return this.sortedDirection === 'asc' ? ' ↑' : ' ↓';
    }
    get sortIconAudience() { return this.getSortIcon('Extole_Audience_Name__c'); }
    get sortIconReport()   { return this.getSortIcon('Source_Report_Name__c'); }
    get sortIconColumn()   { return this.getSortIcon('Identity_Column__c'); }
    get sortIconCadence()  { return this.getSortIcon('Sync_Cadence__c'); }
    get sortIconMembers()  { return this.getSortIcon('Last_Member_Count__c'); }
    get sortIconState()    { return this.getSortIcon('Last_Operation_State__c'); }
    get sortIconLastSync() { return this.getSortIcon('Last_Sync_At__c'); }

    async loadSyncLogs() {
        this.isLoadingLogs = true;
        try {
            const result = await getAudienceSyncLogs();
            const nameMap = new Map();
            (this.configs || []).forEach(c =>
                nameMap.set(c.Config_Key__c, c.Extole_Audience_Name__c));
            this.syncLogs = (result || []).map(log => {
                const audienceName = nameMap.get(log.Config_Key__c) || log.Config_Key__c;
                const idTooltip =
                    `Audience ID: ${log.Audience_Id__c || '—'}\nOperation: ${log.Operation_Id__c || '—'}\nConfig: ${log.Config_Key__c}`;
                return {
                    ...log,
                    audienceName,
                    detailTooltip: log.Detail__c ? `${log.Detail__c}\n\n${idTooltip}` : idTooltip,
                    formattedTimestamp: this.formatTimestamp(log.Timestamp__c, {
                        month: 'short', day: 'numeric',
                        hour: 'numeric', minute: '2-digit', second: '2-digit', hour12: true
                    }),
                    stateClass: this.getStateBadgeClass(log.State__c)
                };
            });
        } catch (error) {
            this.showError('Failed to load audience sync logs.', error);
        } finally {
            this.isLoadingLogs = false;
        }
    }

    decorateConfig(c) {
        const lastSync = this.formatTimestamp(c.Last_Sync_At__c, {
            month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'
        });
        return {
            ...c,
            formattedLastSync: lastSync || '—',
            stateLabel: c.Last_Operation_State__c || 'Draft',
            stateBadgeClass: this.getStateBadgeClass(c.Last_Operation_State__c),
            syncDisabled: NON_TERMINAL.has(c.Last_Operation_State__c),
            extoleAudienceUrl: c.Extole_Audience_Id__c
                ? `https://my.extole.com/audiences-overview/my-audiences#/${c.Extole_Audience_Id__c}`
                : 'https://my.extole.com/audiences-overview/my-audiences#/'
        };
    }

    getStateBadgeClass(state) {
        if (state === 'READY')   return 'audience-state-badge audience-state-ready';
        if (state === 'FAILED')  return 'audience-state-badge audience-state-failed';
        if (NON_TERMINAL.has(state)) return 'audience-state-badge audience-state-running';
        return 'audience-state-badge audience-state-idle';
    }

    get hasConfigs() { return this.configs && this.configs.length > 0; }
    get hasSyncLogs() { return this.syncLogs && this.syncLogs.length > 0; }
    get reportColumnOptions() {
        return (this.reportColumns || []).map(c => ({ label: c, value: c }));
    }
    get hasReportColumns() { return this.reportColumns && this.reportColumns.length > 0; }
    get reportPickerOptions() {
        return (this.availableReports || []).map(r => ({ label: r.name, value: r.id }));
    }
    get cadenceOptions() {
        return [
            { label: 'Manual', value: 'Manual' },
            { label: 'Hourly', value: 'Hourly' },
            { label: 'Daily',  value: 'Daily'  },
            { label: 'Weekly', value: 'Weekly' }
        ];
    }
    get modalTitle() {
        return this.editingConfig && this.editingConfig.Id ? 'Edit Audience' : 'New Audience';
    }

    // ── Modal flow ───────────────────────────────────────────────────────────

    async handleAddAudience() {
        this.editingConfig = {
            Active__c: true,
            Sync_Cadence__c: 'Manual'
        };
        this.modalError = null;
        this.reportColumns = [];
        this.isModalOpen = true;
        await this.loadReports();
    }

    async handleEditAudience(configKey) {
        const cfg = this.configs.find(c => c.Config_Key__c === configKey);
        if (!cfg) return;
        this.editingConfig = { ...cfg };
        this.modalError = null;
        this.isModalOpen = true;
        await this.loadReports();
        if (cfg.Source_Report_Id__c) {
            await this.loadReportColumnsFor(cfg.Source_Report_Id__c);
        }
    }

    async loadReports() {
        this.isLoadingReports = true;
        try {
            this.availableReports = await getAvailableReports();
        } catch (error) {
            this.showError('Failed to load reports.', error);
            this.availableReports = [];
        } finally {
            this.isLoadingReports = false;
        }
    }

    async loadReportColumnsFor(reportId) {
        this.isLoadingColumns = true;
        try {
            this.reportColumns = await getReportColumns({ reportId });
        } catch (error) {
            this.reportColumns = [];
            this.modalError = 'Could not read columns from the selected report.';
        } finally {
            this.isLoadingColumns = false;
        }
    }

    handleCloseModal() {
        this.isModalOpen = false;
        this.editingConfig = {};
        this.modalError = null;
    }

    handleModalFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.detail?.value !== undefined ? event.detail.value : event.target.value;
        this.editingConfig = { ...this.editingConfig, [field]: value };
    }

    async handleModalReportChange(event) {
        const reportId = event.detail.value;
        const report = this.availableReports.find(r => r.id === reportId);
        this.editingConfig = {
            ...this.editingConfig,
            Source_Report_Id__c: reportId,
            Source_Report_Name__c: report ? report.name : '',
            Identity_Column__c: ''
        };
        this.reportColumns = [];
        if (reportId) await this.loadReportColumnsFor(reportId);
    }

    handleModalColumnChange(event) {
        this.editingConfig = { ...this.editingConfig, Identity_Column__c: event.detail.value };
    }

    async handleSaveModal() {
        const name = (this.editingConfig.Extole_Audience_Name__c || '').trim();
        if (!name) {
            this.modalError = 'Extole audience name is required.';
            return;
        }
        if (name.length > 255) {
            this.modalError = 'Extole audience name must be 255 characters or fewer.';
            return;
        }
        this.editingConfig = { ...this.editingConfig, Extole_Audience_Name__c: name };
        if (!this.editingConfig.Source_Report_Id__c) {
            this.modalError = 'Pick a Salesforce report.';
            return;
        }
        if (!this.editingConfig.Identity_Column__c) {
            this.modalError = 'Pick the identity column (the column that holds the email).';
            return;
        }
        this.isSaving = true;
        this.modalError = null;
        try {
            await saveAudienceConfig({ config: this.editingConfig });
            this.handleCloseModal();
            await this.loadConfigs();
            this.showSuccess('Audience saved.');
        } catch (error) {
            this.modalError = (error && error.body && error.body.message) || 'Failed to save audience.';
        } finally {
            this.isSaving = false;
        }
    }

    // ── Row actions ──────────────────────────────────────────────────────────

    async handleRowMenu(event) {
        const action    = event.detail.value;
        const configKey = event.target.dataset.key;
        if (action === 'sync')   await this.handleSyncNow(configKey);
        else if (action === 'edit')   await this.handleEditAudience(configKey);
        else if (action === 'delete') await this.handleDelete(configKey);
    }

    async handleSyncNow(configKey) {
        try {
            await syncAudience({ configKey });
            this.showSuccess('Sync started — polling for state.');
            await this.loadConfigs();
            await this.loadSyncLogs();
            // The Queueable writes the submission log row a moment after enqueue.
            // Reload logs once it's had time to land so the first row doesn't lag
            // until the next 10s poll tick.
            setTimeout(() => this.loadSyncLogs(), 2000);
        } catch (error) {
            this.showError('Failed to start sync.', error);
        }
    }

    async handleDelete(configKey) {
        const cfg = this.configs.find(c => c.Config_Key__c === configKey);
        if (!cfg) return;
        if (!confirm(`Delete audience config "${cfg.Extole_Audience_Name__c}"? This does not delete the audience in Extole.`)) {
            return;
        }
        try {
            await deleteAudienceConfig({ configId: cfg.Id });
            await this.loadConfigs();
            this.showSuccess('Audience config deleted.');
        } catch (error) {
            this.showError('Failed to delete audience config.', error);
        }
    }

    // ── Log table actions ────────────────────────────────────────────────────

    handleRefreshLogs()   { this.loadSyncLogs(); }
    handleRefreshConfigs() { this.loadConfigs(); }

    async handleRunSchedulerNow() {
        try {
            const checked = await runSchedulerNow();
            this.showSuccess(`Scheduler triggered — evaluated ${checked} scheduled audience(s). Watch for state transitions.`);
            await this.loadConfigs();
        } catch (error) {
            this.showError('Failed to run scheduler.', error);
        }
    }
    handleClearLogs()     { this.confirmClearLogs = true; }
    handleCancelClearLogs() { this.confirmClearLogs = false; }
    async handleConfirmClearLogs() {
        this.confirmClearLogs = false;
        this.isClearingLogs = true;
        try {
            const result = await clearAudienceSyncLogs();
            const deleted = (result && result.deletedCount) || 0;
            const remaining = (result && result.remainingCount) || 0;
            this.syncLogs = [];
            if (remaining > 0) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Partial Clear',
                    message: `Cleared ${deleted}. ${remaining} more remain — click again to continue.`,
                    variant: 'warning'
                }));
            } else {
                this.showSuccess(`Cleared ${deleted} audience sync log(s).`);
            }
        } catch (error) {
            this.showError('Failed to clear audience sync log.', error);
        } finally {
            this.isClearingLogs = false;
        }
    }

    // ── Toasts ───────────────────────────────────────────────────────────────

    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message, variant: 'success' }));
    }

    showError(message, error) {
        const detail = error && error.body && error.body.message ? error.body.message : '';
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: detail || message, variant: 'error' }));
    }
}
