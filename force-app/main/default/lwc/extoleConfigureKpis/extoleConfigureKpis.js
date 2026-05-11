import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSettings from '@salesforce/apex/ExtoleController.getSettings';
import saveSettings from '@salesforce/apex/ExtoleController.saveSettings';
import getConfigs from '@salesforce/apex/ExtoleController.getConfigs';
import saveConfig from '@salesforce/apex/ExtoleController.saveConfig';
import deleteConfig from '@salesforce/apex/ExtoleController.deleteConfig';
import getReportTypes from '@salesforce/apex/ExtoleController.getReportTypes';
import getReportColumns from '@salesforce/apex/ExtoleController.getReportColumns';
import triggerSync from '@salesforce/apex/ExtoleController.triggerSync';
import triggerSingleSync from '@salesforce/apex/ExtoleController.triggerSingleSync';
import getSyncLogs from '@salesforce/apex/ExtoleController.getSyncLogs';
import clearSyncLogs from '@salesforce/apex/ExtoleController.clearSyncLogs';
import getScheduleStatus from '@salesforce/apex/ExtoleController.getScheduleStatus';

import LABEL_SAVE_SETTINGS from '@salesforce/label/c.Extole_Settings_SaveSettings';
import LABEL_ADD_REPORT from '@salesforce/label/c.Extole_Settings_AddReport';
import LABEL_REPORT_CONFIG_SECTION from '@salesforce/label/c.Extole_Settings_ReportConfig_Section';
import LABEL_SYNC_MGMT_SECTION from '@salesforce/label/c.Extole_Settings_SyncManagement_Section';
import LABEL_SHOW_KPI_DASHBOARD from '@salesforce/label/c.Extole_Settings_ShowKPIDashboard';
import LABEL_SYNC_CADENCE from '@salesforce/label/c.Extole_Settings_SyncCadence';
import LABEL_NOTIFY_ON_FAILURE from '@salesforce/label/c.Extole_Settings_NotifyOnFailure';
import LABEL_NOTIFY_AFTER_N from '@salesforce/label/c.Extole_Settings_NotifyAfterN';
import LABEL_FAILURE_EMAIL from '@salesforce/label/c.Extole_Settings_FailureEmail';
import LABEL_SYNC_NOW from '@salesforce/label/c.Extole_Settings_SyncNow';
import LABEL_SETTINGS_SAVED from '@salesforce/label/c.Extole_Success_SettingsSaved';
import LABEL_SYNC_TRIGGERED from '@salesforce/label/c.Extole_Success_SyncTriggered';
import LABEL_SYNC_PARTIAL_FAILURE from '@salesforce/label/c.Extole_Warning_SyncPartialFailure';
import LABEL_CONFIG_SAVED from '@salesforce/label/c.Extole_Success_ConfigSaved';
import LABEL_CONFIG_DELETED from '@salesforce/label/c.Extole_Success_ConfigDeleted';
import LABEL_MODAL_STEP1_TITLE from '@salesforce/label/c.Extole_Modal_Step1_Title';
import LABEL_MODAL_STEP2_TITLE from '@salesforce/label/c.Extole_Modal_Step2_Title';
import LABEL_NEXT from '@salesforce/label/c.Extole_Modal_Next';
import LABEL_BACK from '@salesforce/label/c.Extole_Modal_Back';
import LABEL_SAVE from '@salesforce/label/c.Extole_Modal_Save';
import LABEL_CANCEL from '@salesforce/label/c.Extole_Modal_Cancel';
import LABEL_REPORT_DISPLAY_NAME from '@salesforce/label/c.Extole_Report_DisplayName';
import LABEL_CONFIG_DISPLAY_LABEL from '@salesforce/label/c.Extole_Config_DisplayLabel';
import LABEL_CONFIG_VALUE_COLUMN from '@salesforce/label/c.Extole_Config_ValueColumn';
import LABEL_CONFIG_AGGREGATION from '@salesforce/label/c.Extole_Config_Aggregation';
import LABEL_CONFIG_CHART_TYPE from '@salesforce/label/c.Extole_Config_ChartType';
import LABEL_CONFIG_DISPLAY_ORDER from '@salesforce/label/c.Extole_Config_DisplayOrder';
import LABEL_CONFIG_ACTIVE from '@salesforce/label/c.Extole_Config_Active';
import LABEL_CONFIG_COMPARISON_PERIOD from '@salesforce/label/c.Extole_Config_ComparisonPeriod';
import LABEL_SYNC_LOG_REPORT_NAME from '@salesforce/label/c.Extole_SyncLog_ReportName';
import LABEL_SYNC_LOG_DATE_RANGE from '@salesforce/label/c.Extole_SyncLog_DateRange';
import LABEL_SYNC_LOG_TIMESTAMP from '@salesforce/label/c.Extole_SyncLog_Timestamp';
import LABEL_SYNC_LOG_VALUE from '@salesforce/label/c.Extole_SyncLog_Value';
import LABEL_SYNC_LOG_HTTP_STATUS from '@salesforce/label/c.Extole_SyncLog_HttpStatus';
import LABEL_SYNC_LOG_ERROR from '@salesforce/label/c.Extole_SyncLog_Error';
import LABEL_LAST_SYNC from '@salesforce/label/c.Extole_LastSync';
import LABEL_NEVER from '@salesforce/label/c.Extole_Never';
import LABEL_TOOLTIP_DISPLAY_LABEL from '@salesforce/label/c.Extole_Tooltip_DisplayLabel';
import LABEL_TOOLTIP_AGGREGATION from '@salesforce/label/c.Extole_Tooltip_Aggregation';
import LABEL_TOOLTIP_CHART_TYPE from '@salesforce/label/c.Extole_Tooltip_ChartType';
import LABEL_TOOLTIP_VALUE_COLUMN from '@salesforce/label/c.Extole_Tooltip_ValueColumn';
import LABEL_TOOLTIP_COMPARISON_PERIOD from '@salesforce/label/c.Extole_Tooltip_ComparisonPeriod';
import LABEL_SETTINGS_HISTORY_DEPTH from '@salesforce/label/c.Extole_Settings_HistoryDepth';
import LABEL_TOOLTIP_SYNC_CADENCE from '@salesforce/label/c.Extole_Tooltip_SyncCadence';
import LABEL_TOOLTIP_NOTIFY_ON_FAILURE from '@salesforce/label/c.Extole_Tooltip_NotifyOnFailure';
import LABEL_TOOLTIP_NOTIFY_AFTER_N from '@salesforce/label/c.Extole_Tooltip_NotifyAfterN';
import LABEL_TOOLTIP_FAILURE_EMAIL from '@salesforce/label/c.Extole_Tooltip_FailureEmail';
import LABEL_TOOLTIP_SECTION_REPORT_CONFIG from '@salesforce/label/c.Extole_Tooltip_Section_ReportConfig';
import LABEL_TOOLTIP_SECTION_SYNC_MGMT from '@salesforce/label/c.Extole_Tooltip_Section_SyncManagement';
import LABEL_TOOLTIP_DISPLAY_ORDER from '@salesforce/label/c.Extole_Tooltip_DisplayOrder';
import LABEL_TOOLTIP_ACTIVE from '@salesforce/label/c.Extole_Tooltip_Active';

const DEFAULT_SETTINGS = {
    Show_Analytics__c: true,
    Sync_Cadence__c: 'Nightly',
    History_Depth__c: 30,
    Notify_On_Sync_Failure__c: false,
    Notify_After_N_Failures__c: 2,
    Failure_Notification_Email__c: '',
    Last_Sync_Timestamp__c: null
};

export default class ExtoleConfigureKpis extends LightningElement {
    @track settings = { ...DEFAULT_SETTINGS };
    @track hasDirtySettings = false;
    @track isSaving = false;
    @track isSyncing = false;
    @track scheduleWarning = false;

    @track configs = [];
    @track configSortedBy = 'Display_Order__c';
    @track configSortedDirection = 'asc';
    @track isLoadingConfigs = false;

    @track syncLogs = [];
    @track isLoadingLogs = false;
    @track isClearingSyncLogs = false;
    @track confirmClearSync = false;

    // Modal state
    @track isModalOpen = false;
    @track modalStep = 1;
    @track selectedReportTypeId = null;
    @track selectedReportType = null;
    @track editingConfig = {};
    @track rawReportTypes = [];
    @track isLoadingReportTypes = false;
    @track reportColumns = [];
    @track isLoadingColumns = false;
    @track configSaveError = null;
    @track isSavingConfig = false;

    labelSaveSettings = LABEL_SAVE_SETTINGS;
    labelAddReport = LABEL_ADD_REPORT;
    labelReportConfigSection = LABEL_REPORT_CONFIG_SECTION;
    labelSyncManagementSection = LABEL_SYNC_MGMT_SECTION;
    labelShowKPIDashboard = LABEL_SHOW_KPI_DASHBOARD;
    labelSyncCadence = LABEL_SYNC_CADENCE;
    labelNotifyOnFailure = LABEL_NOTIFY_ON_FAILURE;
    labelNotifyAfterN = LABEL_NOTIFY_AFTER_N;
    labelFailureEmail = LABEL_FAILURE_EMAIL;
    labelSyncNow = LABEL_SYNC_NOW;
    labelNext = LABEL_NEXT;
    labelBack = LABEL_BACK;
    labelSave = LABEL_SAVE;
    labelCancel = LABEL_CANCEL;
    labelReportDisplayName = LABEL_REPORT_DISPLAY_NAME;
    labelConfigDisplayLabel = LABEL_CONFIG_DISPLAY_LABEL;
    labelConfigValueColumn = LABEL_CONFIG_VALUE_COLUMN;
    labelConfigAggregation = LABEL_CONFIG_AGGREGATION;
    labelConfigChartType = LABEL_CONFIG_CHART_TYPE;
    labelConfigDisplayOrder = LABEL_CONFIG_DISPLAY_ORDER;
    labelConfigActive = LABEL_CONFIG_ACTIVE;
    labelConfigComparisonPeriod = LABEL_CONFIG_COMPARISON_PERIOD;
    labelSyncLogReportName = LABEL_SYNC_LOG_REPORT_NAME;
    labelSyncLogDateRange = LABEL_SYNC_LOG_DATE_RANGE;
    labelSyncLogTimestamp = LABEL_SYNC_LOG_TIMESTAMP;
    labelSyncLogValue = LABEL_SYNC_LOG_VALUE;
    labelSyncLogHttpStatus = LABEL_SYNC_LOG_HTTP_STATUS;
    labelSyncLogError = LABEL_SYNC_LOG_ERROR;
    labelSettingsHistoryDepth = LABEL_SETTINGS_HISTORY_DEPTH;
    tooltipSectionReportConfig = LABEL_TOOLTIP_SECTION_REPORT_CONFIG;
    tooltipSectionSyncManagement = LABEL_TOOLTIP_SECTION_SYNC_MGMT;
    tooltipDisplayLabel = LABEL_TOOLTIP_DISPLAY_LABEL;
    tooltipAggregation = LABEL_TOOLTIP_AGGREGATION;
    tooltipChartType = LABEL_TOOLTIP_CHART_TYPE;
    tooltipValueColumn = LABEL_TOOLTIP_VALUE_COLUMN;
    tooltipComparisonPeriod = LABEL_TOOLTIP_COMPARISON_PERIOD;
    tooltipDisplayOrder = LABEL_TOOLTIP_DISPLAY_ORDER;
    tooltipActive = LABEL_TOOLTIP_ACTIVE;
    tooltipSyncCadence = LABEL_TOOLTIP_SYNC_CADENCE;
    tooltipNotifyOnFailure = LABEL_TOOLTIP_NOTIFY_ON_FAILURE;
    tooltipNotifyAfterN = LABEL_TOOLTIP_NOTIFY_AFTER_N;
    tooltipFailureEmail = LABEL_TOOLTIP_FAILURE_EMAIL;

    connectedCallback() {
        Promise.all([this.loadSettings(), this.loadConfigs(), this.loadSyncLogs(), this.checkScheduleStatus()]);
    }

    async loadSettings() {
        try {
            const result = await getSettings();
            this.settings = result ? { ...DEFAULT_SETTINGS, ...result } : { ...DEFAULT_SETTINGS };
            this.hasDirtySettings = false;
        } catch (error) {
            this.showError('Failed to load settings.', error);
        }
    }

    async loadConfigs() {
        this.isLoadingConfigs = true;
        try {
            const result = await getConfigs();
            const dateOpts = { month: 'short', day: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' };
            this.configs = (result || []).map(c => ({
                ...c,
                statusLabel: c.Active__c ? 'Active' : 'Inactive',
                statusCellClass: c.Active__c ? 'kpi-status-active' : 'kpi-status-inactive',
                formattedCreatedDate: c.CreatedDate
                    ? new Intl.DateTimeFormat('en-US', dateOpts).format(new Date(c.CreatedDate)) : '—',
                formattedLastModifiedDate: c.LastModifiedDate
                    ? new Intl.DateTimeFormat('en-US', dateOpts).format(new Date(c.LastModifiedDate)) : '—'
            }));
        } catch (error) {
            this.showError('Failed to load report configurations.', error);
        } finally {
            this.isLoadingConfigs = false;
        }
    }

    async loadSyncLogs() {
        this.isLoadingLogs = true;
        try {
            const result = await getSyncLogs();
            this.syncLogs = (result || []).map(log => ({
                ...log,
                statusClass: this.getStatusClass(log.Status__c),
                formattedTimestamp: log.Sync_Timestamp__c
                    ? new Intl.DateTimeFormat('en-US', {
                        month: 'short', day: 'numeric',
                        hour: 'numeric', minute: '2-digit', second: '2-digit', hour12: true
                      }).format(new Date(log.Sync_Timestamp__c))
                    : ''
            }));
        } catch (error) {
            this.showError('Failed to load sync logs.', error);
        } finally {
            this.isLoadingLogs = false;
        }
    }

    async checkScheduleStatus() {
        try {
            const status = await getScheduleStatus();
            const hasCadence = status && status.cadence && status.cadence !== 'None';
            this.scheduleWarning = hasCadence && !status.isScheduled;
        } catch (e) {
            // Non-fatal
        }
    }

    get hasConfigs() { return this.configs && this.configs.length > 0; }
    get hasSyncLogs() { return this.syncLogs && this.syncLogs.length > 0; }

    get lastSyncText() {
        if (this.settings && this.settings.Last_Sync_Timestamp__c) {
            const formatted = new Intl.DateTimeFormat('en-US', {
                month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true
            }).format(new Date(this.settings.Last_Sync_Timestamp__c));
            return `${LABEL_LAST_SYNC}: ${formatted}`;
        }
        return `${LABEL_LAST_SYNC}: ${LABEL_NEVER}`;
    }

    get syncCadenceOptions() {
        return [
            { label: 'Nightly',      value: 'Nightly'      },
            { label: 'Every 12hrs',  value: 'Every 12hrs'  },
            { label: 'Every 6hrs',   value: 'Every 6hrs'   },
            { label: 'Every 30min',  value: 'Every 30min'  }
        ];
    }

    get aggregationOptions() {
        return [
            { label: 'First Row', value: 'FIRST_ROW' },
            { label: 'Sum',       value: 'SUM'       },
            { label: 'Count',     value: 'COUNT'     }
        ];
    }

    get chartTypeOptions() {
        return [
            { label: 'None',      value: 'None'      },
            { label: 'Sparkline', value: 'Sparkline' },
            { label: 'Bar',       value: 'Bar'       }
        ];
    }

    get comparisonPeriodOptions() {
        return [
            { label: '1 day',   value: '1 day'   },
            { label: '7 days',  value: '7 days'  },
            { label: '14 days', value: '14 days' },
            { label: '30 days', value: '30 days' },
            { label: '90 days', value: '90 days' }
        ];
    }

    getKpiSortIcon(field) {
        if (this.configSortedBy !== field) return '';
        return this.configSortedDirection === 'asc' ? ' ↑' : ' ↓';
    }
    get kpiSortIconOrder()    { return this.getKpiSortIcon('Display_Order__c'); }
    get kpiSortIconLabel()    { return this.getKpiSortIcon('Display_Label__c'); }
    get kpiSortIconReport()   { return this.getKpiSortIcon('Report_Name__c'); }
    get kpiSortIconAgg()      { return this.getKpiSortIcon('Aggregation__c'); }
    get kpiSortIconChart()    { return this.getKpiSortIcon('Chart_Type__c'); }
    get kpiSortIconStatus()   { return this.getKpiSortIcon('statusLabel'); }
    get kpiSortIconCreated()  { return this.getKpiSortIcon('CreatedDate'); }
    get kpiSortIconModified() { return this.getKpiSortIcon('LastModifiedDate'); }

    handleConfigSortColumn(event) {
        const field = event.currentTarget.dataset.field;
        if (this.configSortedBy === field) {
            this.configSortedDirection = this.configSortedDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.configSortedBy = field;
            this.configSortedDirection = 'asc';
        }
        const dir = this.configSortedDirection === 'asc' ? 1 : -1;
        this.configs = [...this.configs].sort((a, b) => {
            const av = a[field] ?? '';
            const bv = b[field] ?? '';
            return av < bv ? -dir : av > bv ? dir : 0;
        });
    }

    handleConfigRowMenuSelect(event) {
        const action = event.detail.value;
        const id = event.target.dataset.id;
        const row = this.configs.find(c => c.Id === id);
        if (!row) return;
        if (action === 'edit') this.openModalForEdit(row);
        else if (action === 'delete') this.handleDeleteConfig(row.Id);
    }

    async handleDeleteConfig(configId) {
        try {
            await deleteConfig({ configId });
            this.showSuccess(LABEL_CONFIG_DELETED);
            await this.loadConfigs();
        } catch (error) {
            this.showError('Failed to delete configuration.', error);
        }
    }

    async handleAddReport() {
        this.modalStep = 1;
        this.selectedReportTypeId = null;
        this.selectedReportType = null;
        this.editingConfig = {
            Active__c: true,
            Aggregation__c: 'FIRST_ROW',
            Chart_Type__c: 'Sparkline',
            Comparison_Period__c: '30 days',
            Display_Order__c: this.configs.length + 1
        };
        this.configSaveError = null;
        this.isModalOpen = true;
        await this.loadReportTypes();
    }

    openModalForEdit(config) {
        this.modalStep = 2;
        this.selectedReportTypeId = config.Report_Type__c;
        this.editingConfig = { ...config };
        this.configSaveError = null;
        this.isModalOpen = true;
    }

    async loadReportTypes() {
        this.isLoadingReportTypes = true;
        try {
            const raw = await getReportTypes();
            const parsed = JSON.parse(raw);
            this.rawReportTypes = Array.isArray(parsed) ? parsed : (parsed.data || parsed.report_types || []);
        } catch (error) {
            this.rawReportTypes = [];
            this.showError('Failed to load report types.', error);
        } finally {
            this.isLoadingReportTypes = false;
        }
    }

    handleCloseModal() {
        this.isModalOpen = false;
        this.selectedReportTypeId = null;
        this.selectedReportType = null;
        this.editingConfig = {};
        this.configSaveError = null;
    }

    handleSelectReportType(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedReportTypeId = id;
        this.selectedReportType = this.rawReportTypes.find(rt => (rt.report_runner_id || rt.id) === id);
    }

    async handleModalNext() {
        if (!this.selectedReportTypeId || !this.selectedReportType) return;
        const runner = this.selectedReportType;
        const runnerName = runner.name || runner.display_name || this.selectedReportTypeId;
        this.editingConfig = {
            ...this.editingConfig,
            Report_Type__c: this.selectedReportTypeId,
            Report_Name__c: runnerName,
            Display_Label__c: this.editingConfig.Display_Label__c || runnerName,
            Executor_Type__c: 'RUNNER',
            Value_Column__c: this.editingConfig.Value_Column__c || ''
        };
        this.isLoadingColumns = true;
        this.reportColumns = [];
        try {
            const cols = await getReportColumns({ runnerId: this.selectedReportTypeId });
            this.reportColumns = cols || [];
        } catch (error) {
            this.reportColumns = [];
        } finally {
            this.isLoadingColumns = false;
        }
        this.modalStep = 2;
    }

    async handleModalBack() {
        this.modalStep = 1;
        if (this.rawReportTypes.length === 0) {
            await this.loadReportTypes();
        }
    }

    handleConfigFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        let value;
        if (event.detail && event.detail.checked !== undefined) {
            value = event.detail.checked;
        } else if (event.detail && event.detail.value !== undefined) {
            value = event.detail.value;
        } else {
            value = event.target.value;
        }
        this.editingConfig = { ...this.editingConfig, [field]: value };
    }

    async handleSaveConfig() {
        if (!this.editingConfig.Display_Label__c) {
            this.configSaveError = 'Display Label is required.';
            return;
        }
        this.isSavingConfig = true;
        this.configSaveError = null;
        try {
            const savedId = await saveConfig({ config: this.editingConfig });
            this.handleCloseModal();
            await this.loadConfigs();
            let syncFailed = null;
            if (savedId) {
                try {
                    await triggerSingleSync({ configId: savedId });
                } catch (syncError) {
                    syncFailed = (syncError && syncError.body && syncError.body.message) || 'unknown error';
                }
            }
            if (syncFailed) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Config saved',
                    message: `Immediate sync failed: ${syncFailed}. Tile will populate on next scheduled sync.`,
                    variant: 'warning'
                }));
            } else {
                this.showSuccess(LABEL_CONFIG_SAVED);
            }
        } catch (error) {
            this.configSaveError = (error && error.body && error.body.message) || 'Failed to save configuration.';
        } finally {
            this.isSavingConfig = false;
        }
    }

    get noReportTypeSelected() { return !this.selectedReportTypeId; }
    get valueColumnOptions() { return this.reportColumns.map(col => ({ label: col, value: col })); }
    get hasColumnOptions() { return this.reportColumns && this.reportColumns.length > 0; }
    get isAggregationCount() { return this.editingConfig.Aggregation__c === 'COUNT'; }
    get isStep1() { return this.modalStep === 1; }
    get isStep2() { return this.modalStep === 2; }
    get modalTitle() { return this.modalStep === 1 ? LABEL_MODAL_STEP1_TITLE : LABEL_MODAL_STEP2_TITLE; }
    get step1IndicatorClass() { return this.modalStep === 1 ? 'step-indicator-item step-active' : 'step-indicator-item step-done'; }
    get step2IndicatorClass() { return this.modalStep === 2 ? 'step-indicator-item step-active' : 'step-indicator-item'; }

    isUserGeneratedRunner(runner) {
        if (runner.type === 'SCHEDULED') return true;
        if (runner.type === 'REFRESHING') return false;
        if (runner.tags && Array.isArray(runner.tags) && runner.tags.length > 0) {
            const lowerTags = runner.tags.map(t => String(t).toLowerCase());
            if (lowerTags.every(t => t.startsWith('internal:'))) return false;
        }
        return !!runner.created_by;
    }

    get filteredReportTypes() {
        return this.rawReportTypes
            .filter(rt => this.isUserGeneratedRunner(rt))
            .map(rt => {
                const runnerId = rt.report_runner_id || rt.id;
                return {
                    ...rt,
                    runnerId,
                    displayName: rt.name || rt.display_name || runnerId,
                    rowClass: runnerId === this.selectedReportTypeId ? 'report-row report-row-selected' : 'report-row'
                };
            });
    }

    get noFilteredReportTypes() { return this.filteredReportTypes.length === 0; }

    handleSettingsChange(event) {
        const field = event.currentTarget.dataset.field;
        let value;
        if (event.detail && event.detail.checked !== undefined) {
            value = event.detail.checked;
        } else if (event.detail && event.detail.value !== undefined) {
            value = event.detail.value;
        } else {
            value = event.target.value;
        }
        this.settings = { ...this.settings, [field]: value };
        this.hasDirtySettings = true;
    }

    handleKpiDashboardToggle(event) {
        this.settings = { ...this.settings, Show_Analytics__c: event.detail.checked };
        this.hasDirtySettings = true;
    }

    async handleSaveSettings() {
        if (this.settings.Notify_On_Sync_Failure__c && !this.settings.Failure_Notification_Email__c) {
            this.showError('A notification email address is required when Notify on Sync Failure is enabled.');
            return;
        }
        this.isSaving = true;
        try {
            await saveSettings({ settings: this.settings });
            this.hasDirtySettings = false;
            this.scheduleWarning = false;
            this.showSuccess(LABEL_SETTINGS_SAVED);
        } catch (error) {
            this.showError('Failed to save settings.', error);
        } finally {
            this.isSaving = false;
        }
    }

    async handleSyncNow() {
        if (this.hasDirtySettings) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Unsaved Settings',
                message: 'You have unsaved settings changes. Save your settings before syncing to ensure they take effect.',
                variant: 'warning'
            }));
            return;
        }
        this.isSyncing = true;
        try {
            const failureCount = await triggerSync();
            if (failureCount > 0) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Sync Warning',
                    message: LABEL_SYNC_PARTIAL_FAILURE,
                    variant: 'warning'
                }));
            } else {
                this.showSuccess(LABEL_SYNC_TRIGGERED);
            }
            await Promise.all([this.loadSyncLogs(), this.loadSettings()]);
        } catch (error) {
            this.showError('Sync failed.', error);
        } finally {
            this.isSyncing = false;
        }
    }

    handleClearSyncLogs()  { this.confirmClearSync = true; }
    handleCancelClearSync() { this.confirmClearSync = false; }
    async handleConfirmClearSync() {
        this.confirmClearSync = false;
        this.isClearingSyncLogs = true;
        try {
            await clearSyncLogs();
            this.syncLogs = [];
            this.showSuccess('Sync log cleared.');
        } catch (error) {
            this.showError('Failed to clear sync log.', error);
        } finally {
            this.isClearingSyncLogs = false;
        }
    }

    handleRefreshSyncLogs() { this.loadSyncLogs(); }

    handleCopySyncLogMd() {
        const now = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date());
        const headers = ['Report Name', 'Date Range', 'Status', 'Trigger', 'Timestamp', 'Value', 'HTTP', 'Error'];
        const rows = this.syncLogs.map(l => [
            l.Report_Name__c || '', l.Date_Range__c || '', l.Status__c || '',
            l.Trigger_Type__c || '', l.formattedTimestamp || '', l.Value_Extracted__c || '',
            l.HTTP_Status_Code__c || '', l.Error_Message__c || ''
        ]);
        this.copyToClipboard(this.buildMarkdownTable(`KPI Data Import Log — ${now}`, headers, rows), 'KPI data import log copied to clipboard.');
    }

    getStatusClass(status) {
        const map = { 'SUCCESS': 'log-badge-success', 'FAILED': 'log-badge-failed' };
        return map[status] || 'log-badge-skipped';
    }

    async copyToClipboard(text, successMessage) {
        try {
            await navigator.clipboard.writeText(text);
            this.showSuccess(successMessage);
        } catch (e) {
            this.showError('Could not copy to clipboard.', e);
        }
    }

    buildMarkdownTable(title, headers, rows) {
        const esc = s => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ');
        const header  = `| ${headers.map(esc).join(' | ')} |`;
        const divider = `| ${headers.map(() => '---').join(' | ')} |`;
        const body    = rows.map(r => `| ${r.map(esc).join(' | ')} |`).join('\n');
        return `## ${title}\n\n${header}\n${divider}\n${body || '| (no records) |'}`;
    }

    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message, variant: 'success' }));
    }

    showError(message, error) {
        const detail = error && error.body && error.body.message ? error.body.message : '';
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: detail || message, variant: 'error' }));
    }
}
