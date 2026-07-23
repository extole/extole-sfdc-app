import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getEndpointUrl from '@salesforce/apex/ExtoleWritebackController.getEndpointUrl';
import getWritebackConfigs from '@salesforce/apex/ExtoleWritebackController.getWritebackConfigs';
import saveWritebackConfig from '@salesforce/apex/ExtoleWritebackController.saveWritebackConfig';
import deleteWritebackConfig from '@salesforce/apex/ExtoleWritebackController.deleteWritebackConfig';
import getWritebackLogs from '@salesforce/apex/ExtoleWritebackController.getWritebackLogs';
import clearWritebackLogs from '@salesforce/apex/ExtoleWritebackController.clearWritebackLogs';
import getCurrentUserTimezone from '@salesforce/apex/ExtoleController.getCurrentUserTimezone';

let _rowSeq = 0;
const newRowId = () => `row-${++_rowSeq}`;

export default class ExtoleReceiveEvents extends LightningElement {
    @track endpointUrl = '';
    @track configs = [];
    @track isLoadingConfigs = false;
    @track logs = [];
    @track isLoadingLogs = false;
    @track isClearingLogs = false;
    @track confirmClearLogs = false;

    @track isModalOpen = false;
    @track isSaving = false;
    @track modalError = null;
    @track editingConfig = {};
    @track mappingRows = [];

    userTimezone = null;

    async connectedCallback() {
        try {
            this.userTimezone = await getCurrentUserTimezone();
        } catch {
            this.userTimezone = null;
        }
        await Promise.all([
            this.loadEndpoint(),
            this.loadConfigs(),
            this.loadLogs()
        ]);
    }

    async loadEndpoint() {
        try {
            this.endpointUrl = await getEndpointUrl();
        } catch {
            this.endpointUrl = '(could not determine — check org domain)';
        }
    }

    async loadConfigs() {
        this.isLoadingConfigs = true;
        try {
            const result = await getWritebackConfigs();
            this.configs = (result || []).map((c) => this.decorateConfig(c));
        } catch (error) {
            this.showError('Failed to load writeback rules.', error);
        } finally {
            this.isLoadingConfigs = false;
        }
    }

    async loadLogs() {
        this.isLoadingLogs = true;
        try {
            const result = await getWritebackLogs();
            this.logs = (result || []).map((l) => this.decorateLog(l));
        } catch (error) {
            this.showError('Failed to load event log.', error);
        } finally {
            this.isLoadingLogs = false;
        }
    }

    decorateConfig(c) {
        let mappingCount = 0;
        if (c.Field_Mappings__c) {
            try {
                const arr = JSON.parse(c.Field_Mappings__c);
                mappingCount = Array.isArray(arr) ? arr.length : 0;
            } catch {
                mappingCount = 0;
            }
        }
        return {
            ...c,
            mappingCount:
                mappingCount === 0
                    ? '—'
                    : `${mappingCount} field${mappingCount === 1 ? '' : 's'}`,
            isActive: c.Status__c === 'ACTIVE',
            isInactive: c.Status__c === 'INACTIVE',
            statusBadgeClass:
                c.Status__c === 'ACTIVE'
                    ? 'status-badge status-active'
                    : 'status-badge status-inactive'
        };
    }

    formatTimestamp(value) {
        if (!value) return '';
        const opts = {
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit',
            second: '2-digit',
            hour12: true
        };
        if (this.userTimezone) opts.timeZone = this.userTimezone;
        return new Intl.DateTimeFormat('en-US', opts).format(new Date(value));
    }

    decorateLog(l) {
        const statusClass =
            {
                SUCCESS: 'status-badge status-active',
                FAILED: 'status-badge status-failed',
                SKIPPED: 'status-badge status-skipped'
            }[l.Status__c] || 'status-badge status-skipped';
        return {
            ...l,
            formattedReceivedAt: this.formatTimestamp(l.Received_At__c),
            shortRecordId: l.Record_Id__c
                ? l.Record_Id__c.substring(0, 15)
                : '—',
            recordUrl: l.Record_Id__c ? '/' + l.Record_Id__c : null,
            errorPreview: l.Error__c
                ? l.Error__c.substring(0, 60) +
                  (l.Error__c.length > 60 ? '…' : '')
                : '',
            statusBadgeClass: statusClass,
            reasonClass:
                l.Status__c === 'FAILED'
                    ? 'reason-cell reason-cell-failed'
                    : 'reason-cell'
        };
    }

    get hasConfigs() {
        return this.configs && this.configs.length > 0;
    }
    get hasLogs() {
        return this.logs && this.logs.length > 0;
    }

    get objectTypeOptions() {
        return [
            { label: 'Contact', value: 'Contact' },
            { label: 'Lead', value: 'Lead' }
        ];
    }

    get statusOptions() {
        return [
            { label: 'Active', value: 'ACTIVE' },
            { label: 'Inactive', value: 'INACTIVE' }
        ];
    }

    get modalTitle() {
        return this.editingConfig && this.editingConfig.Id
            ? 'Edit Rule'
            : 'New Rule';
    }

    handleCopyEndpoint() {
        navigator.clipboard
            .writeText(this.endpointUrl)
            .then(() => {
                this.showSuccess('Endpoint URL copied to clipboard.');
            })
            .catch(() => {
                this.showError(
                    'Could not copy — select and copy manually.',
                    null
                );
            });
    }

    handleRefreshConfigs() {
        this.loadConfigs();
    }
    handleRefreshLogs() {
        this.loadLogs();
    }

    handleCopyEventLogMd() {
        const now = new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        }).format(new Date());
        const headers = [
            'Received',
            'Event',
            'Email',
            'Object',
            'Status',
            'SFDC Record',
            'Reason'
        ];
        const rows = this.logs.map((l) => [
            l.formattedReceivedAt || '',
            l.Event_Name__c || '',
            l.Email__c || '',
            l.Object_Type__c || '',
            l.Status__c || '',
            l.Record_Id__c || '',
            l.Error__c || ''
        ]);
        this.copyToClipboard(
            this.buildMarkdownTable(
                `Receive Events Log — ${now}`,
                headers,
                rows
            ),
            'Event log copied to clipboard.'
        );
    }

    handleAddRule() {
        this.editingConfig = { Status__c: 'ACTIVE' };
        this.mappingRows = [];
        this.modalError = null;
        this.isModalOpen = true;
    }

    handleRowMenu(event) {
        const action = event.detail.value;
        const configId = event.target.dataset.id;
        const config = this.configs.find((c) => c.Id === configId);
        if (!config) return;

        if (action === 'edit') {
            this.openEditModal(config);
        } else if (action === 'activate') {
            this.setStatus(config, 'ACTIVE');
        } else if (action === 'deactivate') {
            this.setStatus(config, 'INACTIVE');
        } else if (action === 'delete') {
            this.handleDelete(config);
        }
    }

    openEditModal(config) {
        this.editingConfig = { ...config };
        this.mappingRows = [];
        if (config.Field_Mappings__c) {
            try {
                const parsed = JSON.parse(config.Field_Mappings__c);
                if (Array.isArray(parsed)) {
                    this.mappingRows = parsed.map((m) => ({
                        rowId: newRowId(),
                        extoleKey: m.extoleKey || '',
                        sfdcField: m.sfdcField || ''
                    }));
                }
            } catch {
                this.mappingRows = [];
            }
        }
        this.modalError = null;
        this.isModalOpen = true;
    }

    async setStatus(config, newStatus) {
        try {
            await saveWritebackConfig({
                config: { ...config, Status__c: newStatus }
            });
            await this.loadConfigs();
            this.showSuccess(
                `Rule ${newStatus === 'ACTIVE' ? 'activated' : 'deactivated'}.`
            );
        } catch (error) {
            this.showError('Failed to update rule status.', error);
        }
    }

    async handleDelete(config) {
        const confirmed = await LightningConfirm.open({
            message: `Delete writeback rule for "${config.Event_Name__c}" → ${config.Object_Type__c}? This cannot be undone.`,
            variant: 'headerless',
            label: 'Delete Rule'
        });
        if (!confirmed) return;
        try {
            await deleteWritebackConfig({ configId: config.Id });
            await this.loadConfigs();
            this.showSuccess('Rule deleted.');
        } catch (error) {
            this.showError('Failed to delete rule.', error);
        }
    }

    handleCloseModal() {
        this.isModalOpen = false;
        this.editingConfig = {};
        this.mappingRows = [];
        this.modalError = null;
    }

    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        const value =
            event.detail?.value !== undefined
                ? event.detail.value
                : event.target.value;
        this.editingConfig = { ...this.editingConfig, [field]: value };
    }

    handleMappingChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const col = event.currentTarget.dataset.col;
        const value =
            event.detail?.value !== undefined
                ? event.detail.value
                : event.target.value;
        this.mappingRows = this.mappingRows.map((r) =>
            r.rowId === rowId ? { ...r, [col]: value } : r
        );
    }

    handleAddMapping() {
        this.mappingRows = [
            ...this.mappingRows,
            { rowId: newRowId(), extoleKey: '', sfdcField: '' }
        ];
    }

    handleRemoveMapping(event) {
        const rowId = event.currentTarget.dataset.rowId;
        this.mappingRows = this.mappingRows.filter((r) => r.rowId !== rowId);
    }

    async handleSaveModal() {
        const eventName = (this.editingConfig.Event_Name__c || '').trim();
        if (!eventName) {
            this.modalError = 'Event name is required.';
            return;
        }
        if (!this.editingConfig.Object_Type__c) {
            this.modalError = 'Salesforce object type is required.';
            return;
        }

        const validRows = this.mappingRows.filter(
            (r) => r.extoleKey.trim() && r.sfdcField.trim()
        );
        const mappingsJson =
            validRows.length > 0
                ? JSON.stringify(
                      validRows.map((r) => ({
                          extoleKey: r.extoleKey.trim(),
                          sfdcField: r.sfdcField.trim()
                      }))
                  )
                : null;

        const toSave = {
            ...this.editingConfig,
            Event_Name__c: eventName,
            Field_Mappings__c: mappingsJson
        };

        this.isSaving = true;
        this.modalError = null;
        try {
            await saveWritebackConfig({ config: toSave });
            this.handleCloseModal();
            await this.loadConfigs();
            this.showSuccess('Writeback rule saved.');
        } catch (error) {
            this.modalError =
                (error && error.body && error.body.message) ||
                'Failed to save rule.';
        } finally {
            this.isSaving = false;
        }
    }

    handleClearLogs() {
        this.confirmClearLogs = true;
    }
    handleCancelClearLogs() {
        this.confirmClearLogs = false;
    }

    async handleConfirmClearLogs() {
        this.confirmClearLogs = false;
        this.isClearingLogs = true;
        try {
            const result = await clearWritebackLogs();
            const deleted = (result && result.deletedCount) || 0;
            const remaining = (result && result.remainingCount) || 0;
            this.logs = [];
            if (remaining > 0) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Partial Clear',
                        message: `Cleared ${deleted}. ${remaining} more remain — click again to continue.`,
                        variant: 'warning'
                    })
                );
            } else {
                this.showSuccess(
                    `Cleared ${deleted} event log ${deleted === 1 ? 'entry' : 'entries'}.`
                );
            }
        } catch (error) {
            this.showError('Failed to clear event log.', error);
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
        const esc = (s) => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ');
        const header = `| ${headers.map(esc).join(' | ')} |`;
        const divider = `| ${headers.map(() => '---').join(' | ')} |`;
        const body = rows
            .map((r) => `| ${r.map(esc).join(' | ')} |`)
            .join('\n');
        return `## ${title}\n\n${header}\n${divider}\n${body || '| (no records) |'}`;
    }

    showSuccess(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message,
                variant: 'success'
            })
        );
    }

    showError(message, error) {
        const detail =
            error && error.body && error.body.message ? error.body.message : '';
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: detail || message,
                variant: 'error'
            })
        );
    }
}
