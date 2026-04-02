import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSettings from '@salesforce/apex/ExtoleController.getSettings';
import saveSettings from '@salesforce/apex/ExtoleController.saveSettings';
import getConfigs from '@salesforce/apex/ExtoleController.getConfigs';
import saveConfig from '@salesforce/apex/ExtoleController.saveConfig';
import deleteConfig from '@salesforce/apex/ExtoleController.deleteConfig';
import getReportTypes from '@salesforce/apex/ExtoleController.getReportTypes';
import getReportColumns from '@salesforce/apex/ExtoleController.getReportColumns';
import testConnection from '@salesforce/apex/ExtoleController.testConnection';
import triggerSync from '@salesforce/apex/ExtoleController.triggerSync';
import triggerSingleSync from '@salesforce/apex/ExtoleController.triggerSingleSync';
import getSyncLogs from '@salesforce/apex/ExtoleController.getSyncLogs';
import clearSyncLogs from '@salesforce/apex/ExtoleController.clearSyncLogs';
import clearDebugLogs from '@salesforce/apex/ExtoleController.clearDebugLogs';
import getDebugLogs from '@salesforce/apex/ExtoleController.getDebugLogs';
import getScheduleStatus from '@salesforce/apex/ExtoleController.getScheduleStatus';
import getEventLogs from '@salesforce/apex/ExtoleEventController.getEventLogs';
import clearEventLog from '@salesforce/apex/ExtoleEventController.clearEventLog';

import LABEL_TITLE from '@salesforce/label/c.Extole_Settings_Title';
import LABEL_CONNECTION_SECTION from '@salesforce/label/c.Extole_Settings_Connection_Section';
import LABEL_TEST_CONNECTION from '@salesforce/label/c.Extole_Settings_TestConnection';
import LABEL_SYNC_NOW from '@salesforce/label/c.Extole_Settings_SyncNow';
import LABEL_SAVE_SETTINGS from '@salesforce/label/c.Extole_Settings_SaveSettings';
import LABEL_ADD_REPORT from '@salesforce/label/c.Extole_Settings_AddReport';
import LABEL_REPORT_CONFIG_SECTION from '@salesforce/label/c.Extole_Settings_ReportConfig_Section';
import LABEL_LIST_VIEW_SECTION from '@salesforce/label/c.Extole_Settings_ListView_Section';
import LABEL_SYNC_MGMT_SECTION from '@salesforce/label/c.Extole_Settings_SyncManagement_Section';
import LABEL_DEBUG_SECTION from '@salesforce/label/c.Extole_Settings_Debug_Section';
import LABEL_CLEAR_DEBUG_LOGS from '@salesforce/label/c.Extole_Settings_ClearDebugLogs';
import LABEL_API_TOKEN_NOTE from '@salesforce/label/c.Extole_Settings_ApiTokenNote';
import LABEL_GENERATE_TOKEN from '@salesforce/label/c.Extole_Settings_GenerateToken';
import LABEL_LONG_LIVED_TOKEN from '@salesforce/label/c.Extole_Settings_LongLivedToken';
import LABEL_SHOW_LIST_VIEW from '@salesforce/label/c.Extole_Settings_ShowListView';
import LABEL_SHOW_KPI_DASHBOARD from '@salesforce/label/c.Extole_Settings_ShowKPIDashboard';
import LABEL_LEAD_FIELD from '@salesforce/label/c.Extole_Settings_ListView_Field';
import LABEL_LEAD_VALUE from '@salesforce/label/c.Extole_Settings_ListView_Value';
import LABEL_TRACKING_START from '@salesforce/label/c.Extole_Settings_ListView_StartDate';
import getObjectFields from '@salesforce/apex/ExtoleController.getObjectFields';
import getFieldValues from '@salesforce/apex/ExtoleController.getFieldValues';
import LABEL_SYNC_CADENCE from '@salesforce/label/c.Extole_Settings_SyncCadence';
import LABEL_NOTIFY_ON_FAILURE from '@salesforce/label/c.Extole_Settings_NotifyOnFailure';
import LABEL_NOTIFY_AFTER_N from '@salesforce/label/c.Extole_Settings_NotifyAfterN';
import LABEL_FAILURE_EMAIL from '@salesforce/label/c.Extole_Settings_FailureEmail';
import LABEL_DEBUG_LOGGING from '@salesforce/label/c.Extole_Settings_DebugLogging';
import LABEL_CONNECTED from '@salesforce/label/c.Extole_ConnectionStatus_Connected';
import LABEL_FAILED from '@salesforce/label/c.Extole_ConnectionStatus_Failed';
import LABEL_REPORT_COUNT from '@salesforce/label/c.Extole_Connection_ReportCount';
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
import LABEL_FILTER_CATEGORY from '@salesforce/label/c.Extole_Filter_Category';
import LABEL_PERF_METRICS from '@salesforce/label/c.Extole_Filter_PerformanceMetrics';
import LABEL_REPORT_DISPLAY_NAME from '@salesforce/label/c.Extole_Report_DisplayName';
import LABEL_REPORT_DESCRIPTION from '@salesforce/label/c.Extole_Report_Description';
import LABEL_FAST from '@salesforce/label/c.Extole_Report_Fast';
import LABEL_CONFIG_DISPLAY_LABEL from '@salesforce/label/c.Extole_Config_DisplayLabel';
import LABEL_CONFIG_VALUE_COLUMN from '@salesforce/label/c.Extole_Config_ValueColumn';
import LABEL_CONFIG_AGGREGATION from '@salesforce/label/c.Extole_Config_Aggregation';
import LABEL_CONFIG_CHART_TYPE from '@salesforce/label/c.Extole_Config_ChartType';
import LABEL_CONFIG_DISPLAY_ORDER from '@salesforce/label/c.Extole_Config_DisplayOrder';
import LABEL_CONFIG_ACTIVE from '@salesforce/label/c.Extole_Config_Active';
import LABEL_SYNC_LOG_REPORT_NAME from '@salesforce/label/c.Extole_SyncLog_ReportName';
import LABEL_SYNC_LOG_DATE_RANGE from '@salesforce/label/c.Extole_SyncLog_DateRange';
import LABEL_SYNC_LOG_STATUS from '@salesforce/label/c.Extole_SyncLog_Status';
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
import LABEL_CONFIG_COMPARISON_PERIOD from '@salesforce/label/c.Extole_Config_ComparisonPeriod';
import LABEL_TOOLTIP_COMPARISON_PERIOD from '@salesforce/label/c.Extole_Tooltip_ComparisonPeriod';
import LABEL_SETTINGS_HISTORY_DEPTH from '@salesforce/label/c.Extole_Settings_HistoryDepth';
import LABEL_TOOLTIP_DEBUG_LOGGING from '@salesforce/label/c.Extole_Tooltip_DebugLogging';
import LABEL_DEBUG_CLEAR_ACTIONS_DESC from '@salesforce/label/c.Extole_Debug_ClearActionsDesc';
import LABEL_TOOLTIP_SYNC_CADENCE from '@salesforce/label/c.Extole_Tooltip_SyncCadence';
import LABEL_TOOLTIP_NOTIFY_ON_FAILURE from '@salesforce/label/c.Extole_Tooltip_NotifyOnFailure';
import LABEL_TOOLTIP_NOTIFY_AFTER_N from '@salesforce/label/c.Extole_Tooltip_NotifyAfterN';
import LABEL_TOOLTIP_FAILURE_EMAIL from '@salesforce/label/c.Extole_Tooltip_FailureEmail';

const ATTRIBUTION_COLUMN_DEFAULTS = {
    Contact:     ['Account.Name', 'Email', 'Title'],
    Lead:        ['Email', 'Company', 'Status'],
    Opportunity: ['Account.Name', 'StageName', 'Amount']
};

const DEFAULT_SETTINGS = {
    Show_KPI_Dashboard__c: true,
    Show_List_View__c: false,
    List_View_Object__c: 'Contact',
    List_View_Field__c: '',
    List_View_Value__c: '',
    List_View_Columns__c: '',
    List_View_Start_Date__c: null,
    Sync_Cadence__c: 'Nightly',
    Notify_On_Sync_Failure__c: false,
    Notify_After_N_Failures__c: 2,
    Failure_Notification_Email__c: '',
    Debug_Logging_Enabled__c: false,
    History_Depth__c: 30
};

export default class ExtoleSettings extends LightningElement {
    @track settings = { ...DEFAULT_SETTINGS };
    @track configs = [];
    @track configSortedBy = 'Display_Order__c';
    @track configSortedDirection = 'asc';
    @track syncLogs = [];
    @track connectionResult = null;
    @track isConnected = false;
    @track debugClearResult = null;

    @track isLoading = false;
    @track isLoadingConfigs = false;
    @track isLoadingLogs = false;
    @track debugLogs = [];
    @track isLoadingDebugLogs = false;
    @track eventLogs = [];
    @track isLoadingEventLogs = false;
    @track isClearingEventLogs = false;
    @track isClearingSyncLogs = false;
    @track confirmClearSync = false;
    @track confirmClearEventLog = false;
    @track confirmClearDebug = false;
    @track isTesting = false;
    @track isSaving = false;
    @track isSyncing = false;
    @track isClearingLogs = false;
    @track hasDirtySettings = false;
    @track scheduleWarning = false;

    // List View cascade
    @track attributionObjectOptions = [
        { label: 'Contact',     value: 'Contact'     },
        { label: 'Lead',        value: 'Lead'        },
        { label: 'Opportunity', value: 'Opportunity' }
    ];
    @track attributionFieldOptions = [];
    @track attributionValueOptions = [];
    @track isLoadingAttributionFields = false;
    @track isLoadingAttributionValues = false;

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

    labelTitle = LABEL_TITLE;
    labelConnectionSection = LABEL_CONNECTION_SECTION;
    labelTestConnection = LABEL_TEST_CONNECTION;
    labelSyncNow = LABEL_SYNC_NOW;
    labelSaveSettings = LABEL_SAVE_SETTINGS;
    labelAddReport = LABEL_ADD_REPORT;
    labelReportConfigSection = LABEL_REPORT_CONFIG_SECTION;
    labelListViewSection = LABEL_LIST_VIEW_SECTION;
    labelSyncManagementSection = LABEL_SYNC_MGMT_SECTION;
    labelDebugSection = LABEL_DEBUG_SECTION;
    labelClearDebugLogs = LABEL_CLEAR_DEBUG_LOGS;
    labelApiTokenNote = LABEL_API_TOKEN_NOTE;
    labelGenerateToken = LABEL_GENERATE_TOKEN;
    labelLongLivedToken = LABEL_LONG_LIVED_TOKEN;
    labelShowListView = LABEL_SHOW_LIST_VIEW;
    labelShowKPIDashboard = LABEL_SHOW_KPI_DASHBOARD;
    labelLeadField = LABEL_LEAD_FIELD;
    labelLeadValue = LABEL_LEAD_VALUE;
    labelTrackingStart = LABEL_TRACKING_START;
    labelSyncCadence = LABEL_SYNC_CADENCE;
    labelNotifyOnFailure = LABEL_NOTIFY_ON_FAILURE;
    labelNotifyAfterN = LABEL_NOTIFY_AFTER_N;
    labelFailureEmail = LABEL_FAILURE_EMAIL;
    labelDebugLogging = LABEL_DEBUG_LOGGING;
    labelConnected = LABEL_CONNECTED;
    labelFailed = LABEL_FAILED;
    labelReportCount = LABEL_REPORT_COUNT;
    labelModalStep1Title = LABEL_MODAL_STEP1_TITLE;
    labelModalStep2Title = LABEL_MODAL_STEP2_TITLE;
    labelNext = LABEL_NEXT;
    labelBack = LABEL_BACK;
    labelSave = LABEL_SAVE;
    labelCancel = LABEL_CANCEL;
    labelFilterCategory = LABEL_FILTER_CATEGORY;
    labelPerfMetrics = LABEL_PERF_METRICS;
    labelReportDisplayName = LABEL_REPORT_DISPLAY_NAME;
    labelReportDescription = LABEL_REPORT_DESCRIPTION;
    labelFast = LABEL_FAST;
    labelConfigDisplayLabel = LABEL_CONFIG_DISPLAY_LABEL;
    labelConfigValueColumn = LABEL_CONFIG_VALUE_COLUMN;
    labelConfigAggregation = LABEL_CONFIG_AGGREGATION;
    labelConfigChartType = LABEL_CONFIG_CHART_TYPE;
    labelConfigDisplayOrder = LABEL_CONFIG_DISPLAY_ORDER;
    labelConfigActive = LABEL_CONFIG_ACTIVE;
    labelSyncLogReportName = LABEL_SYNC_LOG_REPORT_NAME;
    labelSyncLogDateRange = LABEL_SYNC_LOG_DATE_RANGE;
    labelSyncLogStatus = LABEL_SYNC_LOG_STATUS;
    labelSyncLogTimestamp = LABEL_SYNC_LOG_TIMESTAMP;
    labelSyncLogValue = LABEL_SYNC_LOG_VALUE;
    labelSyncLogHttpStatus = LABEL_SYNC_LOG_HTTP_STATUS;
    labelSyncLogError = LABEL_SYNC_LOG_ERROR;
    labelLastSync = LABEL_LAST_SYNC;
    labelNever = LABEL_NEVER;
    tooltipDisplayLabel = LABEL_TOOLTIP_DISPLAY_LABEL;
    tooltipAggregation = LABEL_TOOLTIP_AGGREGATION;
    tooltipChartType = LABEL_TOOLTIP_CHART_TYPE;
    tooltipValueColumn = LABEL_TOOLTIP_VALUE_COLUMN;
    tooltipDisplayOrder = 'Controls the left-to-right position of this widget on the dashboard. Lower numbers appear first (1 = leftmost).';
    tooltipActive = 'When unchecked, this report will be hidden from the dashboard and skipped during sync.';
    labelConfigComparisonPeriod = LABEL_CONFIG_COMPARISON_PERIOD;
    tooltipComparisonPeriod = LABEL_TOOLTIP_COMPARISON_PERIOD;
    labelSettingsHistoryDepth = LABEL_SETTINGS_HISTORY_DEPTH;
    tooltipDebugLogging = LABEL_TOOLTIP_DEBUG_LOGGING;
    labelDebugClearActionsDesc = LABEL_DEBUG_CLEAR_ACTIONS_DESC;
    tooltipSyncCadence = LABEL_TOOLTIP_SYNC_CADENCE;
    tooltipNotifyOnFailure = LABEL_TOOLTIP_NOTIFY_ON_FAILURE;
    tooltipNotifyAfterN = LABEL_TOOLTIP_NOTIFY_AFTER_N;
    tooltipFailureEmail = LABEL_TOOLTIP_FAILURE_EMAIL;
    tooltipSectionConnection = 'Connects Salesforce to your Extole account via API. Generate a long-lived token in the Extole Security Center and configure it as a Named Credential.';
    tooltipSectionReportConfig = 'Define which Extole reports appear as KPI tiles on the dashboard. Each config maps a report runner to a single metric.';
    tooltipSectionListView = 'Identify which Salesforce records are Extole-influenced. The List View tab uses these settings to filter and display the people your program has generated.';
    tooltipSectionSyncManagement = 'Control how often Extole data syncs to Salesforce and configure failure alert emails.';
    tooltipSectionDebug = 'Enable detailed HTTP and value-extraction logging to troubleshoot sync issues. Logs are automatically purged after 30 days.';

    connectedCallback() {
        this.loadAll();
    }

    async loadAll() {
        await Promise.all([
            this.loadSettings(),
            this.loadConfigs(),
            this.loadSyncLogs(),
            this.loadDebugLogs(),
            this.loadEventLogs(),
            this.checkScheduleStatus()
        ]);
        // Load attribution dropdowns after settings are loaded
        await this.loadAttributionFields();
        if (this.settings.List_View_Field__c) {
            await this.loadAttributionValues();
        }
    }

    async loadAttributionFields() {
        const obj = this.settings.List_View_Object__c || 'Contact';
        this.isLoadingAttributionFields = true;
        try {
            const fields = await getObjectFields({ objectName: obj });
            this.attributionFieldOptions = fields
                .slice()
                .sort((a, b) => a.label.localeCompare(b.label))
                .map(f => ({ label: f.label, value: f.value }));
        } catch (e) {
            this.attributionFieldOptions = [];
        } finally {
            this.isLoadingAttributionFields = false;
        }
    }

    async loadAttributionValues() {
        const obj   = this.settings.List_View_Object__c || 'Contact';
        const field = this.settings.List_View_Field__c;
        if (!field) return;
        this.isLoadingAttributionValues = true;
        try {
            const vals = await getFieldValues({ objectName: obj, fieldName: field });
            this.attributionValueOptions = vals
                .slice()
                .sort()
                .map(v => ({ label: v, value: v }));
        } catch (e) {
            this.attributionValueOptions = [];
        } finally {
            this.isLoadingAttributionValues = false;
        }
    }

    async handleAttributionObjectChange(event) {
        const val = event.detail.value;
        this.settings = {
            ...this.settings,
            List_View_Object__c: val,
            List_View_Field__c: '',
            List_View_Value__c: '',
            List_View_Columns__c: ''
        };
        this.attributionValueOptions = [];
        this.hasDirtySettings = true;
        await this.loadAttributionFields();
    }

    handleAttributionColumnsChange(event) {
        this.settings = {
            ...this.settings,
            List_View_Columns__c: event.detail.value.join(',')
        };
        this.hasDirtySettings = true;
    }

    async handleAttributionFieldChange(event) {
        const val = event.detail.value;
        this.settings = {
            ...this.settings,
            List_View_Field__c: val,
            List_View_Value__c: ''
        };
        this.attributionValueOptions = [];
        this.hasDirtySettings = true;
        await this.loadAttributionValues();
    }

    async checkScheduleStatus() {
        try {
            const status = await getScheduleStatus();
            // Warn if a cadence is set but no active scheduled job exists
            const hasCadence = status && status.cadence && status.cadence !== 'None';
            this.scheduleWarning = hasCadence && !status.isScheduled;
        } catch (e) {
            // Non-fatal — don't surface scheduling errors on load
        }
    }

    async loadDebugLogs() {
        this.isLoadingDebugLogs = true;
        try {
            const result = await getDebugLogs();
            this.debugLogs = (result || []).map(log => ({
                ...log,
                formattedTimestamp: log.Log_Timestamp__c
                    ? new Intl.DateTimeFormat('en-US', {
                        month: 'short', day: 'numeric',
                        hour: 'numeric', minute: '2-digit', second: '2-digit',
                        hour12: true
                      }).format(new Date(log.Log_Timestamp__c))
                    : ''
            }));
        } catch (error) {
            this.showError('Failed to load debug logs.', error);
        } finally {
            this.isLoadingDebugLogs = false;
        }
    }

    get hasDebugLogs() {
        return this.debugLogs && this.debugLogs.length > 0;
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
                        hour: 'numeric', minute: '2-digit', second: '2-digit',
                        hour12: true
                      }).format(new Date(log.Sync_Timestamp__c))
                    : ''
            }));
        } catch (error) {
            this.showError('Failed to load sync logs.', error);
        } finally {
            this.isLoadingLogs = false;
        }
    }

    async loadEventLogs() {
        this.isLoadingEventLogs = true;
        try {
            const result = await getEventLogs({ configKey: null });
            this.eventLogs = (result || []).map(log => ({
                ...log,
                formattedTimestamp: log.Timestamp__c
                    ? new Intl.DateTimeFormat('en-US', {
                        month: 'short', day: 'numeric',
                        hour: 'numeric', minute: '2-digit', second: '2-digit',
                        hour12: true
                      }).format(new Date(log.Timestamp__c))
                    : '',
                resultClass: this.getResultClass(log.Result__c),
                detailClass: (log.Result__c && log.Result__c !== 'SUCCESS') ? 'error-cell' : 'truncated-cell'
            }));
        } catch (error) {
            this.showError('Failed to load event logs.', error);
        } finally {
            this.isLoadingEventLogs = false;
        }
    }

    handleClearSyncLogs() { this.confirmClearSync = true; }
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

    handleClearEventLogs() { this.confirmClearEventLog = true; }
    handleCancelClearEventLog() { this.confirmClearEventLog = false; }
    async handleConfirmClearEventLog() {
        this.confirmClearEventLog = false;
        this.isClearingEventLogs = true;
        try {
            await clearEventLog();
            this.eventLogs = [];
            this.showSuccess('Event log cleared.');
        } catch (error) {
            this.showError('Failed to clear event log.', error);
        } finally {
            this.isClearingEventLogs = false;
        }
    }

    handleRefreshSyncLogs() { this.loadSyncLogs(); }
    handleRefreshEventLogs() { this.loadEventLogs(); }

    handleCopySyncLogMd() {
        const now = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date());
        const headers = ['Report Name', 'Date Range', 'Status', 'Trigger', 'Timestamp', 'Value', 'HTTP', 'Error'];
        const rows = this.syncLogs.map(l => [
            l.Report_Name__c || '', l.Date_Range__c || '', l.Status__c || '',
            l.Trigger_Type__c || '', l.formattedTimestamp || '', l.Value_Extracted__c || '',
            l.HTTP_Status_Code__c || '', l.Error_Message__c || ''
        ]);
        this.copyToClipboard(this.buildMarkdownTable(`Sync Log — ${now}`, headers, rows), 'Sync log copied to clipboard.');
    }

    handleCopyEventLogMd() {
        const now = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date());
        const headers = ['Config Key', 'Event Type', 'Result', 'Timestamp', 'Detail'];
        const rows = this.eventLogs.map(l => [
            l.Config_Key__c || '', l.Event_Type__c || '', l.Result__c || '',
            l.formattedTimestamp || '', l.Detail__c || ''
        ]);
        this.copyToClipboard(this.buildMarkdownTable(`Event Log — ${now}`, headers, rows), 'Event log copied to clipboard.');
    }

    copyToClipboard(text, successMessage) {
        // navigator.clipboard fails in Salesforce iframes — use execCommand fallback
        const el = document.createElement('textarea');
        el.value = text;
        el.style.position = 'fixed';
        el.style.opacity = '0';
        document.body.appendChild(el);
        el.focus();
        el.select();
        try {
            document.execCommand('copy');
            this.showSuccess(successMessage);
        } catch (e) {
            this.showError('Could not copy to clipboard.', e);
        } finally {
            document.body.removeChild(el);
        }
    }

    buildMarkdownTable(title, headers, rows) {
        const esc = s => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ');
        const header  = `| ${headers.map(esc).join(' | ')} |`;
        const divider = `| ${headers.map(() => '---').join(' | ')} |`;
        const body    = rows.map(r => `| ${r.map(esc).join(' | ')} |`).join('\n');
        return `## ${title}\n\n${header}\n${divider}\n${body || '| (no records) |'}`;
    }

    getStatusClass(status) {
        const map = {
            'SUCCESS': 'log-badge-success',
            'FAILED':  'log-badge-failed'
        };
        return map[status] || 'log-badge-skipped';
    }

    getResultClass(result) {
        const map = {
            'SUCCESS': 'log-badge-success',
            'FAILED':  'log-badge-failed',
            'UNKNOWN': 'log-badge-unknown'
        };
        return map[result] || 'log-badge-skipped';
    }

    get hasConfigs() {
        return this.configs && this.configs.length > 0;
    }

    get hasSyncLogs() {
        return this.syncLogs && this.syncLogs.length > 0;
    }

    get hasEventLogs() {
        return this.eventLogs && this.eventLogs.length > 0;
    }

    get connectionStatusLabel() {
        return this.isConnected ? LABEL_CONNECTED : LABEL_FAILED;
    }

    get connectionBadgeClass() {
        return this.isConnected ? 'connection-badge badge-connected' : 'connection-badge badge-failed';
    }

    get connectionIcon() {
        return this.isConnected ? 'utility:success' : 'utility:error';
    }

    get connectionResultClass() {
        if (!this.connectionResult) return '';
        return this.connectionResult.success ? 'connection-result result-success' : 'connection-result result-error';
    }

    get lastSyncText() {
        if (this.settings && this.settings.Last_Sync_Timestamp__c) {
            const formatted = new Intl.DateTimeFormat('en-US', {
                month: 'short', day: 'numeric',
                hour: 'numeric', minute: '2-digit',
                hour12: true
            }).format(new Date(this.settings.Last_Sync_Timestamp__c));
            return `${LABEL_LAST_SYNC}: ${formatted}`;
        }
        return `${LABEL_LAST_SYNC}: ${LABEL_NEVER}`;
    }

    get isValueDisabled() {
        return this.isLoadingAttributionValues || !this.settings.List_View_Field__c;
    }

    get selectedAttributionColumns() {
        const saved = this.settings.List_View_Columns__c;
        if (saved) return saved.split(',').map(s => s.trim()).filter(Boolean);
        const obj = this.settings.List_View_Object__c || 'Contact';
        return ATTRIBUTION_COLUMN_DEFAULTS[obj] || ATTRIBUTION_COLUMN_DEFAULTS.Contact;
    }

    get syncCadenceOptions() {
        return [
            { label: 'Nightly', value: 'Nightly' },
            { label: 'Every 12hrs', value: 'Every 12hrs' },
            { label: 'Every 6hrs', value: 'Every 6hrs' },
            { label: 'Every 30min', value: 'Every 30min' }
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

    get aggregationOptions() {
        return [
            { label: 'First Row', value: 'FIRST_ROW' },
            { label: 'Sum', value: 'SUM' },
            { label: 'Count', value: 'COUNT' }
        ];
    }

    get chartTypeOptions() {
        return [
            { label: 'None', value: 'None' },
            { label: 'Sparkline', value: 'Sparkline' },
            { label: 'Bar', value: 'Bar' }
        ];
    }

    get comparisonPeriodOptions() {
        return [
            { label: '1 day', value: '1 day' },
            { label: '7 days', value: '7 days' },
            { label: '14 days', value: '14 days' },
            { label: '30 days', value: '30 days' },
            { label: '90 days', value: '90 days' }
        ];
    }

    get noReportTypeSelected() {
        return !this.selectedReportTypeId;
    }

    get valueColumnOptions() {
        return this.reportColumns.map(col => ({ label: col, value: col }));
    }

    get hasColumnOptions() {
        return this.reportColumns && this.reportColumns.length > 0;
    }

    get isAggregationCount() {
        return this.editingConfig.Aggregation__c === 'COUNT';
    }

    get isStep1() {
        return this.modalStep === 1;
    }

    get isStep2() {
        return this.modalStep === 2;
    }

    get modalTitle() {
        return this.modalStep === 1 ? LABEL_MODAL_STEP1_TITLE : LABEL_MODAL_STEP2_TITLE;
    }

    get step1IndicatorClass() {
        return this.modalStep === 1 ? 'step-indicator-item step-active' : 'step-indicator-item step-done';
    }

    get step2IndicatorClass() {
        return this.modalStep === 2 ? 'step-indicator-item step-active' : 'step-indicator-item';
    }

    isUserGeneratedRunner(runner) {
        // User-created scheduled runners have type=SCHEDULED.
        // Platform/system runners have type=REFRESHING.
        if (runner.type === 'SCHEDULED') return true;
        if (runner.type === 'REFRESHING') return false;

        // Fallback for runners with no type field: exclude if tags are all internal:
        if (runner.tags && Array.isArray(runner.tags) && runner.tags.length > 0) {
            const lowerTags = runner.tags.map(t => String(t).toLowerCase());
            if (lowerTags.every(t => t.startsWith('internal:'))) return false;
        }

        // Last resort: non-empty created_by suggests user ownership
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
                    rowClass: runnerId === this.selectedReportTypeId
                        ? 'report-row report-row-selected'
                        : 'report-row'
                };
            });
    }

    get noFilteredReportTypes() {
        return this.filteredReportTypes.length === 0;
    }

    // Event handlers
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

    async handleSaveSettings() {
        if (this.settings.Show_List_View__c) {
            if (!this.settings.List_View_Field__c || !this.settings.List_View_Value__c) {
                this.showError('Please select both an Extole Field and Extole Value before saving.');
                return;
            }
        }
        this.isSaving = true;
        try {
            await saveSettings({ settings: this.settings });
            this.hasDirtySettings = false;
            this.scheduleWarning = false;
            this.showSuccess(LABEL_SETTINGS_SAVED);
            this.dispatchEvent(new CustomEvent('settingssaved', { detail: this.settings }));
        } catch (error) {
            this.showError('Failed to save settings.', error);
        } finally {
            this.isSaving = false;
        }
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
            if (this.settings && this.settings.Debug_Logging_Enabled__c) {
                await this.loadDebugLogs();
            }
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
                this.isConnected = true;
                this.connectionResult = null;
                this.showSuccess(LABEL_SYNC_TRIGGERED);
            }
            await Promise.all([this.loadSyncLogs(), this.loadSettings(), this.loadDebugLogs(), this.loadEventLogs()]);
        } catch (error) {
            this.isConnected = false;
            this.showError('Sync failed.', error);
        } finally {
            this.isSyncing = false;
        }
    }

    handleClearDebugLogs() {
        this.confirmClearDebug = true;
    }

    handleCancelClearDebugLogs() {
        this.confirmClearDebug = false;
    }

    async handleConfirmClearDebugLogs() {
        this.confirmClearDebug = false;
        this.isClearingLogs = true;
        this.debugClearResult = null;
        try {
            const count = await clearDebugLogs();
            this.debugClearResult = `Cleared ${count} debug log(s).`;
            this.showSuccess(`Cleared ${count} debug log(s).`);
            await this.loadDebugLogs();
        } catch (error) {
            this.showError('Failed to clear debug logs.', error);
        } finally {
            this.isClearingLogs = false;
        }
    }

    handleConfigRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if (action === 'edit') {
            this.openModalForEdit(row);
        } else if (action === 'delete') {
            this.handleDeleteConfig(row.Id);
        }
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
            // Support array or {data: [...]} wrapper
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
        this.selectedReportType = this.rawReportTypes.find(
            rt => (rt.report_runner_id || rt.id) === id
        );
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
            // Non-fatal — user can still type a value if columns can't be fetched
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
            // Auto-sync after every save so the tile reflects changes immediately
            if (savedId) {
                try {
                    await triggerSingleSync({ configId: savedId });
                } catch (syncError) {
                    // Non-fatal — tile will populate on next scheduled sync
                }
            }
            this.showSuccess(LABEL_CONFIG_SAVED);
        } catch (error) {
            this.configSaveError = (error && error.body && error.body.message) || 'Failed to save configuration.';
        } finally {
            this.isSavingConfig = false;
        }
    }

    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message,
            variant: 'success'
        }));
    }

    showError(message, error) {
        const detail = error && error.body && error.body.message ? error.body.message : '';
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: detail || message,
            variant: 'error'
        }));
    }
}
