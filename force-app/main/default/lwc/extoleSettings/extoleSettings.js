import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSettings from '@salesforce/apex/ExtoleController.getSettings';
import saveSettings from '@salesforce/apex/ExtoleController.saveSettings';
import getConfigs from '@salesforce/apex/ExtoleController.getConfigs';
import saveConfig from '@salesforce/apex/ExtoleController.saveConfig';
import deleteConfig from '@salesforce/apex/ExtoleController.deleteConfig';
import getReportTypes from '@salesforce/apex/ExtoleController.getReportTypes';
import testConnection from '@salesforce/apex/ExtoleController.testConnection';
import triggerSync from '@salesforce/apex/ExtoleController.triggerSync';
import getSyncLogs from '@salesforce/apex/ExtoleController.getSyncLogs';
import clearDebugLogs from '@salesforce/apex/ExtoleController.clearDebugLogs';
import clearOrphanedSnapshots from '@salesforce/apex/ExtoleController.clearOrphanedSnapshots';

import LABEL_TITLE from '@salesforce/label/c.Extole_Settings_Title';
import LABEL_CONNECTION_SECTION from '@salesforce/label/c.Extole_Settings_Connection_Section';
import LABEL_TEST_CONNECTION from '@salesforce/label/c.Extole_Settings_TestConnection';
import LABEL_SYNC_NOW from '@salesforce/label/c.Extole_Settings_SyncNow';
import LABEL_SAVE_SETTINGS from '@salesforce/label/c.Extole_Settings_SaveSettings';
import LABEL_ADD_REPORT from '@salesforce/label/c.Extole_Settings_AddReport';
import LABEL_REPORT_CONFIG_SECTION from '@salesforce/label/c.Extole_Settings_ReportConfig_Section';
import LABEL_LEAD_ATTRIB_SECTION from '@salesforce/label/c.Extole_Settings_LeadAttribution_Section';
import LABEL_SYNC_MGMT_SECTION from '@salesforce/label/c.Extole_Settings_SyncManagement_Section';
import LABEL_DEBUG_SECTION from '@salesforce/label/c.Extole_Settings_Debug_Section';
import LABEL_CLEAR_DEBUG_LOGS from '@salesforce/label/c.Extole_Settings_ClearDebugLogs';
import LABEL_CLEAR_ORPHANED from '@salesforce/label/c.Extole_Settings_ClearOrphanedData';
import LABEL_API_TOKEN_NOTE from '@salesforce/label/c.Extole_Settings_ApiTokenNote';
import LABEL_GENERATE_TOKEN from '@salesforce/label/c.Extole_Settings_GenerateToken';
import LABEL_LONG_LIVED_TOKEN from '@salesforce/label/c.Extole_Settings_LongLivedToken';
import LABEL_SHOW_LEAD_ATTRIB from '@salesforce/label/c.Extole_Settings_ShowLeadAttrib';
import LABEL_RAF_LEAD_FIELD from '@salesforce/label/c.Extole_Settings_RAFLeadField';
import LABEL_RAF_LEAD_VALUE from '@salesforce/label/c.Extole_Settings_RAFLeadValue';
import LABEL_RAF_TRACKING_START from '@salesforce/label/c.Extole_Settings_RAFTrackingStart';
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
import LABEL_CONFIG_DATE_RANGE from '@salesforce/label/c.Extole_Config_DateRange';
import LABEL_CONFIG_DISPLAY_ORDER from '@salesforce/label/c.Extole_Config_DisplayOrder';
import LABEL_CONFIG_ACTIVE from '@salesforce/label/c.Extole_Config_Active';
import LABEL_SYNC_LOG_REPORT_NAME from '@salesforce/label/c.Extole_SyncLog_ReportName';
import LABEL_SYNC_LOG_DATE_RANGE from '@salesforce/label/c.Extole_SyncLog_DateRange';
import LABEL_SYNC_LOG_STATUS from '@salesforce/label/c.Extole_SyncLog_Status';
import LABEL_SYNC_LOG_TIMESTAMP from '@salesforce/label/c.Extole_SyncLog_Timestamp';
import LABEL_SYNC_LOG_VALUE from '@salesforce/label/c.Extole_SyncLog_Value';
import LABEL_SYNC_LOG_HTTP_STATUS from '@salesforce/label/c.Extole_SyncLog_HttpStatus';
import LABEL_SYNC_LOG_POLL_ATTEMPTS from '@salesforce/label/c.Extole_SyncLog_PollAttempts';
import LABEL_SYNC_LOG_ERROR from '@salesforce/label/c.Extole_SyncLog_Error';
import LABEL_LAST_SYNC from '@salesforce/label/c.Extole_LastSync';
import LABEL_NEVER from '@salesforce/label/c.Extole_Never';
import LABEL_TOOLTIP_DISPLAY_LABEL from '@salesforce/label/c.Extole_Tooltip_DisplayLabel';
import LABEL_TOOLTIP_AGGREGATION from '@salesforce/label/c.Extole_Tooltip_Aggregation';
import LABEL_TOOLTIP_CHART_TYPE from '@salesforce/label/c.Extole_Tooltip_ChartType';
import LABEL_TOOLTIP_DATE_RANGE from '@salesforce/label/c.Extole_Tooltip_DateRange';
import LABEL_TOOLTIP_VALUE_COLUMN from '@salesforce/label/c.Extole_Tooltip_ValueColumn';

const DEFAULT_SETTINGS = {
    Show_Lead_Attribution__c: false,
    RAF_Lead_Field__c: 'LeadSource',
    RAF_Lead_Value__c: 'Referral',
    RAF_Tracking_Start_Date__c: null,
    Sync_Cadence__c: 'Nightly',
    Notify_On_Sync_Failure__c: false,
    Notify_After_N_Failures__c: 2,
    Failure_Notification_Email__c: '',
    Debug_Logging_Enabled__c: false
};

export default class ExtoleSettings extends LightningElement {
    @track settings = { ...DEFAULT_SETTINGS };
    @track configs = [];
    @track syncLogs = [];
    @track connectionResult = null;
    @track isConnected = false;
    @track debugClearResult = null;

    @track isLoading = false;
    @track isLoadingConfigs = false;
    @track isLoadingLogs = false;
    @track isTesting = false;
    @track isSaving = false;
    @track isSyncing = false;
    @track isClearingLogs = false;
    @track isClearingOrphans = false;

    // Modal state
    @track isModalOpen = false;
    @track modalStep = 1;
    @track selectedReportTypeId = null;
    @track selectedReportType = null;
    @track editingConfig = {};
    @track rawReportTypes = [];
    @track isLoadingReportTypes = false;
    @track selectedCategory = 'Performance & Metrics';
    @track configSaveError = null;
    @track isSavingConfig = false;

    labelTitle = LABEL_TITLE;
    labelConnectionSection = LABEL_CONNECTION_SECTION;
    labelTestConnection = LABEL_TEST_CONNECTION;
    labelSyncNow = LABEL_SYNC_NOW;
    labelSaveSettings = LABEL_SAVE_SETTINGS;
    labelAddReport = LABEL_ADD_REPORT;
    labelReportConfigSection = LABEL_REPORT_CONFIG_SECTION;
    labelLeadAttributionSection = LABEL_LEAD_ATTRIB_SECTION;
    labelSyncManagementSection = LABEL_SYNC_MGMT_SECTION;
    labelDebugSection = LABEL_DEBUG_SECTION;
    labelClearDebugLogs = LABEL_CLEAR_DEBUG_LOGS;
    labelClearOrphanedData = LABEL_CLEAR_ORPHANED;
    labelApiTokenNote = LABEL_API_TOKEN_NOTE;
    labelGenerateToken = LABEL_GENERATE_TOKEN;
    labelLongLivedToken = LABEL_LONG_LIVED_TOKEN;
    labelShowLeadAttrib = LABEL_SHOW_LEAD_ATTRIB;
    labelRAFLeadField = LABEL_RAF_LEAD_FIELD;
    labelRAFLeadValue = LABEL_RAF_LEAD_VALUE;
    labelRAFTrackingStart = LABEL_RAF_TRACKING_START;
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
    labelConfigDateRange = LABEL_CONFIG_DATE_RANGE;
    labelConfigDisplayOrder = LABEL_CONFIG_DISPLAY_ORDER;
    labelConfigActive = LABEL_CONFIG_ACTIVE;
    labelSyncLogReportName = LABEL_SYNC_LOG_REPORT_NAME;
    labelSyncLogDateRange = LABEL_SYNC_LOG_DATE_RANGE;
    labelSyncLogStatus = LABEL_SYNC_LOG_STATUS;
    labelSyncLogTimestamp = LABEL_SYNC_LOG_TIMESTAMP;
    labelSyncLogValue = LABEL_SYNC_LOG_VALUE;
    labelSyncLogHttpStatus = LABEL_SYNC_LOG_HTTP_STATUS;
    labelSyncLogPollAttempts = LABEL_SYNC_LOG_POLL_ATTEMPTS;
    labelSyncLogError = LABEL_SYNC_LOG_ERROR;
    labelLastSync = LABEL_LAST_SYNC;
    labelNever = LABEL_NEVER;
    tooltipDisplayLabel = LABEL_TOOLTIP_DISPLAY_LABEL;
    tooltipAggregation = LABEL_TOOLTIP_AGGREGATION;
    tooltipChartType = LABEL_TOOLTIP_CHART_TYPE;
    tooltipDateRange = LABEL_TOOLTIP_DATE_RANGE;
    tooltipValueColumn = LABEL_TOOLTIP_VALUE_COLUMN;

    connectedCallback() {
        this.loadAll();
    }

    async loadAll() {
        await Promise.all([
            this.loadSettings(),
            this.loadConfigs(),
            this.loadSyncLogs()
        ]);
    }

    async loadSettings() {
        try {
            const result = await getSettings();
            this.settings = result ? { ...DEFAULT_SETTINGS, ...result } : { ...DEFAULT_SETTINGS };
        } catch (error) {
            this.showError('Failed to load settings.', error);
        }
    }

    async loadConfigs() {
        this.isLoadingConfigs = true;
        try {
            const result = await getConfigs();
            this.configs = (result || []).map(c => ({
                ...c,
                activeLabel: c.Active__c ? 'Yes' : 'No'
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
                statusClass: this.getStatusClass(log.Status__c)
            }));
        } catch (error) {
            this.showError('Failed to load sync logs.', error);
        } finally {
            this.isLoadingLogs = false;
        }
    }

    getStatusClass(status) {
        if (status === 'SUCCESS') return 'status-success';
        if (status === 'FAILED') return 'status-failed';
        return 'status-skipped';
    }

    get hasConfigs() {
        return this.configs && this.configs.length > 0;
    }

    get hasSyncLogs() {
        return this.syncLogs && this.syncLogs.length > 0;
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
        if (this.settings && this.settings.Last_Sync__c) {
            return `${LABEL_LAST_SYNC}: ${this.settings.Last_Sync__c}`;
        }
        return `${LABEL_LAST_SYNC}: ${LABEL_NEVER}`;
    }

    get syncCadenceOptions() {
        return [
            { label: 'Nightly', value: 'Nightly' },
            { label: 'Every 12hrs', value: 'Every 12hrs' },
            { label: 'Every 6hrs', value: 'Every 6hrs' }
        ];
    }

    get configColumns() {
        return [
            { label: 'Display Label', fieldName: 'Display_Label__c', type: 'text' },
            { label: 'Report Type', fieldName: 'Report_Type__c', type: 'text' },
            { label: 'Date Range', fieldName: 'Date_Range__c', type: 'text' },
            { label: 'Chart Type', fieldName: 'Chart_Type__c', type: 'text' },
            { label: 'Active', fieldName: 'activeLabel', type: 'text' },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [
                        { label: 'Edit', name: 'edit' },
                        { label: 'Delete', name: 'delete' }
                    ]
                }
            }
        ];
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

    get dateRangeOptions() {
        return [
            { label: 'Rolling 30', value: 'Rolling 30' },
            { label: 'Rolling 90', value: 'Rolling 90' },
            { label: 'YTD', value: 'YTD' }
        ];
    }

    get valueColumnOptions() {
        if (!this.selectedReportType || !this.selectedReportType.preview_columns) return [];
        return this.selectedReportType.preview_columns.map(col => ({
            label: col,
            value: col
        }));
    }

    get noReportTypeSelected() {
        return !this.selectedReportTypeId;
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

    get categoryOptions() {
        const categories = new Set();
        this.rawReportTypes.forEach(rt => {
            if (rt.category) categories.add(rt.category);
        });
        const opts = [...categories].map(c => ({ label: c, value: c }));
        opts.unshift({ label: 'All', value: 'All' });
        return opts;
    }

    get filteredReportTypes() {
        return this.rawReportTypes
            .filter(rt => {
                const hasJson = rt.formats && rt.formats.includes('JSON');
                const validType = ['CONFIGURED', 'SPARK', 'SQL'].includes(rt.type);
                const catMatch = this.selectedCategory === 'All' || rt.category === this.selectedCategory;
                return hasJson && validType && catMatch;
            })
            .map(rt => ({
                ...rt,
                isSql: rt.type === 'SQL',
                rowClass: rt.report_type_id === this.selectedReportTypeId
                    ? 'report-row report-row-selected'
                    : 'report-row'
            }));
    }

    get noFilteredReportTypes() {
        return this.filteredReportTypes.length === 0;
    }

    // Event handlers
    handleSettingsChange(event) {
        const field = event.currentTarget.dataset.field;
        const type = event.currentTarget.type;
        let value;
        if (type === 'checkbox') {
            value = event.target.checked;
        } else {
            value = event.target.value;
        }
        this.settings = { ...this.settings, [field]: value };
    }

    async handleSaveSettings() {
        this.isSaving = true;
        try {
            await saveSettings({ settings: this.settings });
            this.showSuccess(LABEL_SETTINGS_SAVED);
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
        }
    }

    async handleSyncNow() {
        this.isSyncing = true;
        try {
            await triggerSync();
            this.showSuccess(LABEL_SYNC_TRIGGERED);
            await this.loadSyncLogs();
        } catch (error) {
            this.showError('Sync failed.', error);
        } finally {
            this.isSyncing = false;
        }
    }

    async handleClearDebugLogs() {
        this.isClearingLogs = true;
        this.debugClearResult = null;
        try {
            const count = await clearDebugLogs();
            this.debugClearResult = `Cleared ${count} debug log(s).`;
        } catch (error) {
            this.showError('Failed to clear debug logs.', error);
        } finally {
            this.isClearingLogs = false;
        }
    }

    async handleClearOrphanedData() {
        this.isClearingOrphans = true;
        this.debugClearResult = null;
        try {
            const count = await clearOrphanedSnapshots();
            this.debugClearResult = `Cleared ${count} orphaned snapshot(s).`;
        } catch (error) {
            this.showError('Failed to clear orphaned data.', error);
        } finally {
            this.isClearingOrphans = false;
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
            Date_Range__c: 'Rolling 30',
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
        this.selectedReportType = this.rawReportTypes.find(rt => rt.report_type_id === id);
    }

    handleModalNext() {
        if (!this.selectedReportTypeId || !this.selectedReportType) return;
        // Pre-fill config fields from selected report type
        this.editingConfig = {
            ...this.editingConfig,
            Report_Type__c: this.selectedReportTypeId,
            Report_Name__c: this.selectedReportType.display_name || this.selectedReportType.name,
            Display_Label__c: this.editingConfig.Display_Label__c || this.selectedReportType.display_name || '',
            Executor_Type__c: this.selectedReportType.type || '',
            Value_Column__c: this.editingConfig.Value_Column__c || (
                this.selectedReportType.preview_columns && this.selectedReportType.preview_columns.length > 0
                    ? this.selectedReportType.preview_columns[0]
                    : ''
            )
        };
        this.modalStep = 2;
    }

    handleModalBack() {
        this.modalStep = 1;
    }

    handleCategoryChange(event) {
        this.selectedCategory = event.target.value;
    }

    handleConfigFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        const type = event.currentTarget.type;
        let value;
        if (type === 'checkbox') {
            value = event.target.checked;
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
            await saveConfig({ config: this.editingConfig });
            this.showSuccess(LABEL_CONFIG_SAVED);
            this.handleCloseModal();
            await this.loadConfigs();
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
