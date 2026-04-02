import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEventConfigs from '@salesforce/apex/ExtoleEventController.getEventConfigs';
import deleteEventConfig from '@salesforce/apex/ExtoleEventController.deleteEventConfig';
import deactivateEventConfig from '@salesforce/apex/ExtoleEventController.deactivateEventConfig';
import checkEventUsage from '@salesforce/apex/ExtoleEventController.checkEventUsage';
import clearEventLog from '@salesforce/apex/ExtoleEventController.clearEventLog';

import LABEL_TITLE from '@salesforce/label/c.Extole_EC_Title';
import LABEL_SUBTITLE from '@salesforce/label/c.Extole_EC_Subtitle';
import LABEL_ADD_EVENT from '@salesforce/label/c.Extole_EC_AddEvent';
import LABEL_CLEAR_EVENT_LOG from '@salesforce/label/c.Extole_EC_ClearEventLog';
import LABEL_EMPTY_TITLE from '@salesforce/label/c.Extole_EC_EmptyState_Title';
import LABEL_EMPTY_BODY from '@salesforce/label/c.Extole_EC_EmptyState_Body';
import LABEL_EMPTY_ACTION from '@salesforce/label/c.Extole_EC_EmptyState_Action';
import LABEL_COL_EVENT_NAME from '@salesforce/label/c.Extole_EC_Col_EventName';
import LABEL_COL_TRIGGER from '@salesforce/label/c.Extole_EC_Col_Trigger';
import LABEL_COL_STATUS from '@salesforce/label/c.Extole_EC_Col_Status';
import LABEL_COL_LAST_DEPLOYED from '@salesforce/label/c.Extole_EC_Col_LastDeployed';
import LABEL_COL_LAST_FIRE from '@salesforce/label/c.Extole_EC_Col_LastFire';
import LABEL_ACTION_EDIT from '@salesforce/label/c.Extole_EC_Action_Edit';
import LABEL_ACTION_DELETE from '@salesforce/label/c.Extole_EC_Action_Delete';
import LABEL_STATUS_ACTIVE from '@salesforce/label/c.Extole_EC_Status_Active';
import LABEL_STATUS_INACTIVE from '@salesforce/label/c.Extole_EC_Status_Inactive';
import LABEL_STATUS_DRAFT from '@salesforce/label/c.Extole_EC_Status_Draft';
import LABEL_STATUS_DEPLOY_FAILED from '@salesforce/label/c.Extole_EC_Status_DeployFailed';
import LABEL_DELETE_TITLE from '@salesforce/label/c.Extole_EC_Delete_Title';
import LABEL_DELETE_CHECKING from '@salesforce/label/c.Extole_EC_Delete_Checking';
import LABEL_DELETE_NOT_FOUND from '@salesforce/label/c.Extole_EC_Delete_NotFound';
import LABEL_DELETE_FOUND from '@salesforce/label/c.Extole_EC_Delete_Found';
import LABEL_DELETE_UNKNOWN from '@salesforce/label/c.Extole_EC_Delete_Unknown';
import LABEL_DELETE_CAMPAIGN from '@salesforce/label/c.Extole_EC_Delete_Campaign';
import LABEL_DELETE_CONFIRM from '@salesforce/label/c.Extole_EC_Delete_Confirm';
import LABEL_DELETE_ANYWAY from '@salesforce/label/c.Extole_EC_Delete_DeleteAnyway';
import LABEL_DEACTIVATE from '@salesforce/label/c.Extole_EC_Delete_Deactivate';
import LABEL_DELETE_CANCEL from '@salesforce/label/c.Extole_EC_Delete_Cancel';
import LABEL_DELETE_SUCCESS from '@salesforce/label/c.Extole_EC_Delete_Success';
import LABEL_DEACTIVATE_SUCCESS from '@salesforce/label/c.Extole_EC_Deactivate_Success';
import LABEL_EVENT_LOG_CLEARED from '@salesforce/label/c.Extole_EC_EventLog_Cleared';
import LABEL_ERROR_LOAD_CONFIGS from '@salesforce/label/c.Extole_EC_Error_LoadConfigs';
import LABEL_ERROR_DELETE from '@salesforce/label/c.Extole_EC_Error_Delete';
import LABEL_ERROR_CLEAR_LOG from '@salesforce/label/c.Extole_EC_Error_ClearLog';

const USAGE_CHECK_TIMEOUT_MS = 10000;

export default class ExtoleEventConfigurator extends LightningElement {
    @track configs = [];
    @track sortedBy = 'Event_Name__c';
    @track sortedDirection = 'asc';
    @track isLoading = false;
    @track isClearingLog = false;

    // Modal: Add/Edit
    @track isModalOpen = false;
    @track editingConfig = null;

    // Modal: Delete
    @track isDeleteModalOpen = false;
    @track deletingConfig = null;
    @track deleteCheckStatus = 'CHECKING'; // CHECKING | NOT_FOUND | FOUND | UNKNOWN
    @track deleteCheckCampaignName = null;
    @track isDeleting = false;

    // Labels
    labelTitle = LABEL_TITLE;
    tooltipSectionEventConfig = 'Map Salesforce record changes to Extole events. Each config deploys a Record-Triggered Flow that fires when your trigger conditions are met.';
    labelSubtitle = LABEL_SUBTITLE;
    labelAddEvent = LABEL_ADD_EVENT;
    labelClearEventLog = LABEL_CLEAR_EVENT_LOG;
    labelEmptyTitle = LABEL_EMPTY_TITLE;
    labelEmptyBody = LABEL_EMPTY_BODY;
    labelEmptyAction = LABEL_EMPTY_ACTION;
    labelColEventName = LABEL_COL_EVENT_NAME;
    labelColTrigger = LABEL_COL_TRIGGER;
    labelColStatus = LABEL_COL_STATUS;
    labelColLastDeployed = LABEL_COL_LAST_DEPLOYED;
    labelColLastFire = LABEL_COL_LAST_FIRE;
    labelDeleteTitle = LABEL_DELETE_TITLE;
    labelDeleteChecking = LABEL_DELETE_CHECKING;
    labelDeleteCancel = LABEL_DELETE_CANCEL;
    labelDeleteConfirm = LABEL_DELETE_CONFIRM;
    labelDeleteAnyway = LABEL_DELETE_ANYWAY;
    labelDeactivate = LABEL_DEACTIVATE;
    labelDeleteCampaign = LABEL_DELETE_CAMPAIGN;

    connectedCallback() {
        this.loadConfigs();
    }

    async loadConfigs() {
        this.isLoading = true;
        try {
            const result = await getEventConfigs();
            this.configs = (result || []).map(c => this.enrichConfig(c));
        } catch (error) {
            this.showError(LABEL_ERROR_LOAD_CONFIGS, error);
        } finally {
            this.isLoading = false;
        }
    }

    enrichConfig(c) {
        const dateOpts = { month: 'short', day: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' };
        return {
            ...c,
            triggerLabel: this.buildTriggerLabel(c),
            statusLabel: this.getStatusLabel(c.Status__c),
            statusCellClass: this.getStatusCellClass(c.Status__c),
            formattedCreatedDate: c.CreatedDate
                ? new Intl.DateTimeFormat('en-US', dateOpts).format(new Date(c.CreatedDate)) : '—',
            formattedLastDeployed: c.Last_Deployed__c
                ? new Intl.DateTimeFormat('en-US', dateOpts).format(new Date(c.Last_Deployed__c)) : '—',
            formattedLastFire: c.Last_Attempted_At__c
                ? new Intl.DateTimeFormat('en-US', dateOpts).format(new Date(c.Last_Attempted_At__c)) : '—'
        };
    }

    getStatusCellClass(status) {
        const map = {
            'ACTIVE':        'ec-status-active',
            'INACTIVE':      'ec-status-inactive',
            'DRAFT':         'ec-status-draft',
            'DEPLOY_FAILED': 'ec-status-failed'
        };
        return map[status] || '';
    }

    buildTriggerLabel(c) {
        const obj = c.Trigger_Object__c || '';
        const type = c.Trigger_Type__c || '';
        if (type === 'CREATED') return `${obj} — Record Created`;
        if (type === 'UPDATED') return `${obj} — Record Updated`;
        if (type === 'FIELD_EQUALS') {
            return `${obj} — ${c.Trigger_Field__c || 'Field'} = ${c.Trigger_Value__c || ''}`;
        }
        if (type === 'FIELD_CHANGES') {
            return `${obj} — ${c.Trigger_Field__c || 'Field'}: ${c.Trigger_From_Value__c || '*'} → ${c.Trigger_To_Value__c || '*'}`;
        }
        return obj;
    }

    getStatusLabel(status) {
        const map = {
            'ACTIVE': LABEL_STATUS_ACTIVE,
            'INACTIVE': LABEL_STATUS_INACTIVE,
            'DRAFT': LABEL_STATUS_DRAFT,
            'DEPLOY_FAILED': LABEL_STATUS_DEPLOY_FAILED
        };
        return map[status] || status || '';
    }

    get hasConfigs() {
        return this.configs && this.configs.length > 0;
    }

    getSortIcon(field) {
        if (this.sortedBy !== field) return '';
        return this.sortedDirection === 'asc' ? ' ↑' : ' ↓';
    }
    get sortIconEventName()    { return this.getSortIcon('Event_Name__c'); }
    get sortIconTrigger()      { return this.getSortIcon('triggerLabel'); }
    get sortIconStatus()       { return this.getSortIcon('statusLabel'); }
    get sortIconCreated()      { return this.getSortIcon('CreatedDate'); }
    get sortIconLastDeployed() { return this.getSortIcon('Last_Deployed__c'); }
    get sortIconLastFire()     { return this.getSortIcon('Last_Attempted_At__c'); }

    handleSortColumn(event) {
        const field = event.currentTarget.dataset.field;
        if (this.sortedBy === field) {
            this.sortedDirection = this.sortedDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortedBy = field;
            this.sortedDirection = 'asc';
        }
        const dir = this.sortedDirection === 'asc' ? 1 : -1;
        this.configs = [...this.configs].sort((a, b) => {
            const av = a[field] ?? '';
            const bv = b[field] ?? '';
            return av < bv ? -dir : av > bv ? dir : 0;
        });
    }

    handleRowMenuSelect(event) {
        const action = event.detail.value;
        const key = event.target.dataset.key;
        const config = this.configs.find(c => c.Config_Key__c === key);
        if (!config) return;
        if (action === 'edit') {
            this.editingConfig = config;
            this.isModalOpen = true;
        } else if (action === 'delete') {
            this.openDeleteModal(config);
        }
    }

    // ── Add Event ──────────────────────────────────────────────────────────

    handleAddEvent() {
        this.editingConfig = null;
        this.isModalOpen = true;
    }

    handleEmptyAction() {
        this.handleAddEvent();
    }

    // ── Row actions ────────────────────────────────────────────────────────

    handleRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if (action === 'edit') {
            this.editingConfig = row;
            this.isModalOpen = true;
        } else if (action === 'delete') {
            this.openDeleteModal(row);
        }
    }

    // ── Modal: Add/Edit ────────────────────────────────────────────────────

    handleModalClose() {
        this.isModalOpen = false;
        this.editingConfig = null;
    }

    handleDeployed() {
        this.isModalOpen = false;
        this.editingConfig = null;
        this.loadConfigs();
    }

    // ── Modal: Delete ──────────────────────────────────────────────────────

    openDeleteModal(config) {
        this.deletingConfig = config;
        this.deleteCheckCampaignName = null;
        this.isDeleting = false;
        this.isDeleteModalOpen = true;
        // DRAFT, DEPLOY_FAILED, INACTIVE: no active flow to deactivate — skip usage check
        if (config.Status__c === 'DRAFT' || config.Status__c === 'DEPLOY_FAILED' || config.Status__c === 'INACTIVE') {
            this.deleteCheckStatus = 'NOT_FOUND';
        } else {
            this.deleteCheckStatus = 'CHECKING';
            this.runUsageCheck(config.Event_Name__c);
        }
    }

    async runUsageCheck(eventName) {
        const timeoutPromise = new Promise(resolve => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => resolve({ status: 'UNKNOWN' }), USAGE_CHECK_TIMEOUT_MS);
        });
        try {
            const checkPromise = checkEventUsage({ eventName });
            const result = await Promise.race([checkPromise, timeoutPromise]);
            const parsed = typeof result === 'string' ? JSON.parse(result) : result;
            this.deleteCheckStatus = parsed.status || 'UNKNOWN';
            this.deleteCheckCampaignName = parsed.campaignName || null;
        } catch (error) {
            this.deleteCheckStatus = 'UNKNOWN';
        }
    }

    get isDeleteChecking() {
        return this.deleteCheckStatus === 'CHECKING';
    }

    get deleteBodyMessage() {
        if (this.deleteCheckStatus === 'NOT_FOUND') return LABEL_DELETE_NOT_FOUND;
        if (this.deleteCheckStatus === 'FOUND') return LABEL_DELETE_FOUND;
        return LABEL_DELETE_UNKNOWN;
    }

    get showCampaignName() {
        return this.deleteCheckStatus === 'FOUND' && this.deleteCheckCampaignName;
    }

    get showDeleteButton() {
        return this.deleteCheckStatus === 'NOT_FOUND';
    }

    get showDeactivateButton() {
        return this.deleteCheckStatus === 'FOUND' || this.deleteCheckStatus === 'UNKNOWN';
    }

    get showDeleteAnywayButton() {
        return this.deleteCheckStatus === 'FOUND' || this.deleteCheckStatus === 'UNKNOWN';
    }

    get isDeleteButtonDisabled() {
        return this.isDeleteChecking || this.isDeleting;
    }

    handleCloseDeleteModal() {
        this.isDeleteModalOpen = false;
        this.deletingConfig = null;
    }

    async handleConfirmDelete() {
        this.isDeleting = true;
        try {
            await deleteEventConfig({ configKey: this.deletingConfig.Config_Key__c });
            this.showSuccess(LABEL_DELETE_SUCCESS);
            this.isDeleteModalOpen = false;
            this.deletingConfig = null;
            await this.loadConfigs();
        } catch (error) {
            this.showError(LABEL_ERROR_DELETE, error);
        } finally {
            this.isDeleting = false;
        }
    }

    async handleDeactivate() {
        this.isDeleting = true;
        try {
            await deactivateEventConfig({ configKey: this.deletingConfig.Config_Key__c });
            this.showSuccess(LABEL_DEACTIVATE_SUCCESS);
            this.isDeleteModalOpen = false;
            this.deletingConfig = null;
            await this.loadConfigs();
        } catch (error) {
            this.showError(LABEL_ERROR_DELETE, error);
        } finally {
            this.isDeleting = false;
        }
    }

    async handleDeleteAnyway() {
        await this.handleConfirmDelete();
    }

    // ── Clear event log ────────────────────────────────────────────────────

    async handleClearEventLog() {
        this.isClearingLog = true;
        try {
            await clearEventLog();
            this.showSuccess(LABEL_EVENT_LOG_CLEARED);
        } catch (error) {
            this.showError(LABEL_ERROR_CLEAR_LOG, error);
        } finally {
            this.isClearingLog = false;
        }
    }

    // ── Toast helpers ──────────────────────────────────────────────────────

    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message, variant: 'success' }));
    }

    showError(message, error) {
        const detail = error && error.body && error.body.message ? error.body.message : '';
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: detail || message, variant: 'error' }));
    }
}
