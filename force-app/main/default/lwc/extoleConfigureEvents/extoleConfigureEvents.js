import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import testConnection from '@salesforce/apex/ExtoleController.testConnection';
import getSettings from '@salesforce/apex/ExtoleController.getSettings';
import saveSettings from '@salesforce/apex/ExtoleController.saveSettings';
import getEventLogs from '@salesforce/apex/ExtoleEventController.getEventLogs';
import clearEventLog from '@salesforce/apex/ExtoleEventController.clearEventLog';
import getEventFireLogs from '@salesforce/apex/ExtoleEventController.getEventFireLogs';
import clearEventFireLogs from '@salesforce/apex/ExtoleEventController.clearEventFireLogs';
import getDebugLogs from '@salesforce/apex/ExtoleController.getDebugLogs';
import clearDebugLogs from '@salesforce/apex/ExtoleController.clearDebugLogs';

import LABEL_CONNECTION_SECTION from '@salesforce/label/c.Extole_Settings_Connection_Section';
import LABEL_TEST_CONNECTION from '@salesforce/label/c.Extole_Settings_TestConnection';
import LABEL_API_TOKEN_NOTE from '@salesforce/label/c.Extole_Settings_ApiTokenNote';
import LABEL_CONNECTED from '@salesforce/label/c.Extole_ConnectionStatus_Connected';
import LABEL_FAILED from '@salesforce/label/c.Extole_ConnectionStatus_Failed';
import LABEL_REPORT_COUNT from '@salesforce/label/c.Extole_Connection_ReportCount';
import LABEL_DEBUG_SECTION from '@salesforce/label/c.Extole_Settings_Debug_Section';
import LABEL_CLEAR_DEBUG_LOGS from '@salesforce/label/c.Extole_Settings_ClearDebugLogs';
import LABEL_DEBUG_LOGGING from '@salesforce/label/c.Extole_Settings_DebugLogging';
import LABEL_TOOLTIP_DEBUG_LOGGING from '@salesforce/label/c.Extole_Tooltip_DebugLogging';
import LABEL_DEBUG_CLEAR_ACTIONS_DESC from '@salesforce/label/c.Extole_Debug_ClearActionsDesc';
import LABEL_SETTINGS_SAVED from '@salesforce/label/c.Extole_Success_SettingsSaved';
import LABEL_TOOLTIP_SECTION_CONNECTION from '@salesforce/label/c.Extole_Tooltip_Section_Connection';
import LABEL_TOOLTIP_SECTION_DEBUG from '@salesforce/label/c.Extole_Tooltip_Section_Debug';

const DEFAULT_SETTINGS = { Debug_Logging_Enabled__c: false };

export default class ExtoleConfigureEvents extends LightningElement {
    @track settings = { ...DEFAULT_SETTINGS };
    @track hasDirtySettings = false;
    @track isSaving = false;

    @track connectionResult = null;
    @track isConnected = false;
    @track isTesting = false;

    @track eventLogs = [];
    @track isLoadingEventLogs = false;
    @track isClearingEventLogs = false;
    @track confirmClearEventLog = false;

    @track fireLogs = [];
    @track isLoadingFireLogs = false;
    @track isClearingFireLogs = false;
    @track confirmClearFireLog = false;

    @track debugLogs = [];
    @track isLoadingDebugLogs = false;
    @track debugClearResult = null;
    @track isClearingLogs = false;
    @track confirmClearDebug = false;

    labelConnectionSection = LABEL_CONNECTION_SECTION;
    labelTestConnection = LABEL_TEST_CONNECTION;
    labelApiTokenNote = LABEL_API_TOKEN_NOTE;
    labelReportCount = LABEL_REPORT_COUNT;
    labelDebugSection = LABEL_DEBUG_SECTION;
    labelClearDebugLogs = LABEL_CLEAR_DEBUG_LOGS;
    labelDebugLogging = LABEL_DEBUG_LOGGING;
    tooltipDebugLogging = LABEL_TOOLTIP_DEBUG_LOGGING;
    labelDebugClearActionsDesc = LABEL_DEBUG_CLEAR_ACTIONS_DESC;
    tooltipSectionConnection = LABEL_TOOLTIP_SECTION_CONNECTION;
    tooltipSectionDebug = LABEL_TOOLTIP_SECTION_DEBUG;

    connectedCallback() {
        Promise.all([this.loadSettings(), this.loadEventLogs(), this.loadEventFireLogs(), this.loadDebugLogs()]);
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

    async loadEventLogs() {
        this.isLoadingEventLogs = true;
        try {
            const result = await getEventLogs({ configKey: null });
            this.eventLogs = (result || []).map(log => ({
                ...log,
                formattedTimestamp: log.Timestamp__c
                    ? new Intl.DateTimeFormat('en-US', {
                        month: 'short', day: 'numeric',
                        hour: 'numeric', minute: '2-digit', second: '2-digit', hour12: true
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

    async loadDebugLogs() {
        this.isLoadingDebugLogs = true;
        try {
            const result = await getDebugLogs();
            this.debugLogs = (result || []).map(log => ({
                ...log,
                formattedTimestamp: log.Log_Timestamp__c
                    ? new Intl.DateTimeFormat('en-US', {
                        month: 'short', day: 'numeric',
                        hour: 'numeric', minute: '2-digit', second: '2-digit', hour12: true
                      }).format(new Date(log.Log_Timestamp__c))
                    : ''
            }));
        } catch (error) {
            this.showError('Failed to load debug logs.', error);
        } finally {
            this.isLoadingDebugLogs = false;
        }
    }

    get hasEventLogs() { return this.eventLogs && this.eventLogs.length > 0; }
    get hasFireLogs() { return this.fireLogs && this.fireLogs.length > 0; }
    get hasDebugLogs() { return this.debugLogs && this.debugLogs.length > 0; }

    get connectionStatusLabel() { return this.isConnected ? LABEL_CONNECTED : LABEL_FAILED; }
    get connectionBadgeClass() { return this.isConnected ? 'connection-badge badge-connected' : 'connection-badge badge-failed'; }
    get connectionIcon() { return this.isConnected ? 'utility:success' : 'utility:error'; }

    getResultClass(result) {
        const map = { 'SUCCESS': 'log-badge-success', 'FAILED': 'log-badge-failed', 'UNKNOWN': 'log-badge-unknown' };
        return map[result] || 'log-badge-skipped';
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
            if (this.settings.Debug_Logging_Enabled__c) {
                await this.loadDebugLogs();
            }
        }
    }

    async loadEventFireLogs() {
        this.isLoadingFireLogs = true;
        try {
            const result = await getEventFireLogs();
            this.fireLogs = (result || []).map(log => ({
                ...log,
                formattedTimestamp: log.Timestamp__c
                    ? new Intl.DateTimeFormat('en-US', {
                        month: 'short', day: 'numeric',
                        hour: 'numeric', minute: '2-digit', second: '2-digit', hour12: true
                      }).format(new Date(log.Timestamp__c))
                    : '',
                resultClass: log.Result__c === 'SUCCESS' ? 'log-badge-success' : 'log-badge-failed',
                detailClass: log.Result__c !== 'SUCCESS' ? 'error-cell' : 'truncated-cell'
            }));
        } catch (error) {
            this.showError('Failed to load event fire logs.', error);
        } finally {
            this.isLoadingFireLogs = false;
        }
    }

    handleRefreshFireLogs() { this.loadEventFireLogs(); }
    handleClearFireLogs()   { this.confirmClearFireLog = true; }
    handleCancelClearFireLog() { this.confirmClearFireLog = false; }
    async handleConfirmClearFireLog() {
        this.confirmClearFireLog = false;
        this.isClearingFireLogs = true;
        try {
            const result = await clearEventFireLogs();
            const deleted = (result && result.deletedCount) || 0;
            const remaining = (result && result.remainingCount) || 0;
            this.fireLogs = [];
            if (remaining > 0) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Partial Clear',
                    message: `Cleared ${deleted}. ${remaining} more remain — click again to continue.`,
                    variant: 'warning'
                }));
            } else {
                this.showSuccess(`Cleared ${deleted} event fire log(s).`);
            }
        } catch (error) {
            this.showError('Failed to clear event fire log.', error);
        } finally {
            this.isClearingFireLogs = false;
        }
    }

    handleCopyFireLogMd() {
        const now = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date());
        const headers = ['Event Name', 'Record ID', 'Result', 'HTTP', 'Timestamp', 'Detail'];
        const rows = this.fireLogs.map(l => [
            l.Event_Name__c || '', l.Record_Id__c || '',
            l.Result__c || '', l.HTTP_Status__c != null ? l.HTTP_Status__c : '',
            l.formattedTimestamp || '', l.Detail__c || ''
        ]);
        this.copyToClipboard(
            this.buildMarkdownTable(`Event Fire Log — ${now}`, headers, rows),
            'Event fire log copied to clipboard.'
        );
    }

    handleClearEventLogs() { this.confirmClearEventLog = true; }
    handleCancelClearEventLog() { this.confirmClearEventLog = false; }
    async handleConfirmClearEventLog() {
        this.confirmClearEventLog = false;
        this.isClearingEventLogs = true;
        try {
            const result = await clearEventLog();
            const deleted = (result && result.deletedCount) || 0;
            const remaining = (result && result.remainingCount) || 0;
            this.eventLogs = [];
            if (remaining > 0) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Partial Clear',
                    message: `Cleared ${deleted}. ${remaining} more remain — click again to continue.`,
                    variant: 'warning'
                }));
            } else {
                this.showSuccess(`Cleared ${deleted} configuration history entries.`);
            }
        } catch (error) {
            this.showError('Failed to clear event log.', error);
        } finally {
            this.isClearingEventLogs = false;
        }
    }
    handleRefreshEventLogs() { this.loadEventLogs(); }

    handleCopyEventLogMd() {
        const now = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date());
        const headers = ['Config Key', 'Event Type', 'Result', 'Timestamp', 'Detail'];
        const rows = this.eventLogs.map(l => [
            l.Config_Key__c || '', l.Event_Type__c || '', l.Result__c || '',
            l.formattedTimestamp || '', l.Detail__c || ''
        ]);
        this.copyToClipboard(
            this.buildMarkdownTable(`Event Configuration History — ${now}`, headers, rows),
            'Event configuration history copied to clipboard.'
        );
    }

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
        this.isSaving = true;
        try {
            await saveSettings({ settings: this.settings });
            this.hasDirtySettings = false;
            this.showSuccess(LABEL_SETTINGS_SAVED);
        } catch (error) {
            this.showError('Failed to save settings.', error);
        } finally {
            this.isSaving = false;
        }
    }

    handleClearDebugLogs() { this.confirmClearDebug = true; }
    handleCancelClearDebugLogs() { this.confirmClearDebug = false; }
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
