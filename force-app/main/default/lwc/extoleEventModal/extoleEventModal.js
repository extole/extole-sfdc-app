import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableObjects from '@salesforce/apex/ExtoleEventController.getAvailableObjects';
import getFieldsForObject from '@salesforce/apex/ExtoleEventController.getFieldsForObject';
import getPicklistValues from '@salesforce/apex/ExtoleEventController.getPicklistValues';
import previewPayload from '@salesforce/apex/ExtoleEventController.previewPayload';
import saveEventConfig from '@salesforce/apex/ExtoleEventController.saveEventConfig';
import deployEventConfig from '@salesforce/apex/ExtoleEventController.deployEventConfig';
import pollDeployStatus from '@salesforce/apex/ExtoleEventController.pollDeployStatus';
import suggestUniqueEventName from '@salesforce/apex/ExtoleEventController.suggestUniqueEventName';

import LABEL_STEP1_TITLE from '@salesforce/label/c.Extole_EC_Modal_Step1_Title';
import LABEL_STEP2_TITLE from '@salesforce/label/c.Extole_EC_Modal_Step2_Title';
import LABEL_STEP3_TITLE from '@salesforce/label/c.Extole_EC_Modal_Step3_Title';
import LABEL_EDIT_TITLE from '@salesforce/label/c.Extole_EC_Modal_EditTitle';
import LABEL_CANCEL from '@salesforce/label/c.Extole_Modal_Cancel';
import LABEL_NEXT from '@salesforce/label/c.Extole_Modal_Next';
import LABEL_BACK from '@salesforce/label/c.Extole_Modal_Back';
import LABEL_TRIGGER_OBJECT from '@salesforce/label/c.Extole_EC_Trigger_ObjectLabel';
import LABEL_TRIGGER_OBJECT_PH from '@salesforce/label/c.Extole_EC_Trigger_ObjectPlaceholder';
import LABEL_TRIGGER_CONDITION from '@salesforce/label/c.Extole_EC_Trigger_ConditionLabel';
import LABEL_TRIGGER_FIELD from '@salesforce/label/c.Extole_EC_Trigger_FieldLabel';
import LABEL_TRIGGER_VALUE from '@salesforce/label/c.Extole_EC_Trigger_ValueLabel';
import LABEL_TRIGGER_FROM from '@salesforce/label/c.Extole_EC_Trigger_FromValueLabel';
import LABEL_TRIGGER_TO from '@salesforce/label/c.Extole_EC_Trigger_ToValueLabel';
import LABEL_PRESET_SECTION from '@salesforce/label/c.Extole_EC_Preset_SectionTitle';
import LABEL_PRESET_LEAD_CREATED from '@salesforce/label/c.Extole_EC_Preset_LeadCreated';
import LABEL_PRESET_LEAD_CONVERTED from '@salesforce/label/c.Extole_EC_Preset_LeadConverted';
import LABEL_PRESET_OPP_WON from '@salesforce/label/c.Extole_EC_Preset_OpportunityWon';
import LABEL_PRESET_CUSTOM from '@salesforce/label/c.Extole_EC_Preset_Custom';
import LABEL_PRESET_LEAD_CREATED_DESC from '@salesforce/label/c.Extole_EC_Preset_LeadCreated_Desc';
import LABEL_PRESET_LEAD_CONVERTED_DESC from '@salesforce/label/c.Extole_EC_Preset_LeadConverted_Desc';
import LABEL_PRESET_OPP_WON_DESC from '@salesforce/label/c.Extole_EC_Preset_OpportunityWon_Desc';
import LABEL_PRESET_CUSTOM_DESC from '@salesforce/label/c.Extole_EC_Preset_Custom_Desc';
import LABEL_EVENT_NAME from '@salesforce/label/c.Extole_EC_Fields_EventNameLabel';
import LABEL_EVENT_NAME_TOOLTIP from '@salesforce/label/c.Extole_EC_Fields_EventNameTooltip';
import LABEL_APP_TYPE_NOTE from '@salesforce/label/c.Extole_EC_Fields_AppTypeNote';
import LABEL_NULL_NOTE from '@salesforce/label/c.Extole_EC_Fields_NullNote';
import LABEL_PARAM_NAME from '@salesforce/label/c.Extole_EC_Fields_ParamNameLabel';
import LABEL_PARAM_VALUE from '@salesforce/label/c.Extole_EC_Fields_ParamValueLabel';
import LABEL_ADD_PARAM from '@salesforce/label/c.Extole_EC_Fields_AddParam';
import LABEL_REMOVE_PARAM from '@salesforce/label/c.Extole_EC_Fields_RemoveParam';
import LABEL_STATIC_VALUE from '@salesforce/label/c.Extole_EC_Fields_StaticValue';
import LABEL_SFDC_FIELD from '@salesforce/label/c.Extole_EC_Fields_SFDCField';
import LABEL_FIELD_PICKER from '@salesforce/label/c.Extole_EC_Fields_FieldPickerLabel';
import LABEL_STATIC_VALUE_INPUT from '@salesforce/label/c.Extole_EC_Fields_StaticValueLabel';
import LABEL_REVIEW_SUMMARY from '@salesforce/label/c.Extole_EC_Review_SummarySection';
import LABEL_REVIEW_OBJECT from '@salesforce/label/c.Extole_EC_Review_ObjectLabel';
import LABEL_REVIEW_TRIGGER from '@salesforce/label/c.Extole_EC_Review_TriggerLabel';
import LABEL_REVIEW_EVENT_NAME from '@salesforce/label/c.Extole_EC_Review_EventNameLabel';
import LABEL_REVIEW_MAPPINGS from '@salesforce/label/c.Extole_EC_Review_MappingsSection';
import LABEL_REVIEW_ARTIFACTS from '@salesforce/label/c.Extole_EC_Review_ArtifactsSection';
import LABEL_REVIEW_APEX from '@salesforce/label/c.Extole_EC_Review_ApexClassLabel';
import LABEL_REVIEW_FLOW from '@salesforce/label/c.Extole_EC_Review_FlowNameLabel';
import LABEL_REVIEW_ARTIFACTS_NOTE from '@salesforce/label/c.Extole_EC_Review_ArtifactsNote';
import LABEL_REVIEW_TEST_RECORD from '@salesforce/label/c.Extole_EC_Review_TestRecord';
import LABEL_REVIEW_TEST_DESC from '@salesforce/label/c.Extole_EC_Review_TestRecordDesc';
import LABEL_REVIEW_TEST_BUTTON from '@salesforce/label/c.Extole_EC_Review_TestButton';
import LABEL_REVIEW_DEPLOY from '@salesforce/label/c.Extole_EC_Review_DeployButton';
import LABEL_REVIEW_DEPLOYING from '@salesforce/label/c.Extole_EC_Review_Deploying';
import LABEL_REVIEW_DEPLOY_SUCCESS from '@salesforce/label/c.Extole_EC_Review_DeploySuccess';
import LABEL_REVIEW_DEPLOY_FAILED from '@salesforce/label/c.Extole_EC_Review_DeployFailed';
import LABEL_REVIEW_DIFF_SECTION from '@salesforce/label/c.Extole_EC_Review_DiffSection';
import LABEL_REVIEW_DIFF_NOTE from '@salesforce/label/c.Extole_EC_Review_DiffNote';
import LABEL_REVIEW_DIFF_ADDED from '@salesforce/label/c.Extole_EC_Review_DiffAdded';
import LABEL_REVIEW_DIFF_REMOVED from '@salesforce/label/c.Extole_EC_Review_DiffRemoved';
import LABEL_REVIEW_DIFF_CHANGED from '@salesforce/label/c.Extole_EC_Review_DiffChanged';
import LABEL_REVIEW_RECORD_ID from '@salesforce/label/c.Extole_EC_Review_RecordIdLabel';
import LABEL_REVIEW_PAYLOAD_PREVIEW from '@salesforce/label/c.Extole_EC_Review_PayloadPreview';
import LABEL_REVIEW_TRIGGER_CHANGED from '@salesforce/label/c.Extole_EC_Review_TriggerChanged';
import LABEL_ERROR_LOAD_OBJECTS from '@salesforce/label/c.Extole_EC_Error_LoadObjects';
import LABEL_ERROR_LOAD_FIELDS from '@salesforce/label/c.Extole_EC_Error_LoadFields';
import LABEL_ERROR_PREVIEW from '@salesforce/label/c.Extole_EC_Error_Preview';
import LABEL_ERROR_SAVE_REQUIRED from '@salesforce/label/c.Extole_EC_Error_SaveRequired';
import LABEL_ERROR_EVENT_NAME_REQUIRED from '@salesforce/label/c.Extole_EC_Error_EventNameRequired';
import LABEL_ERROR_EVENT_NAME_DUPLICATE from '@salesforce/label/c.Extole_EC_Error_EventNameDuplicate';
import LABEL_ERROR_OBJECT_REQUIRED from '@salesforce/label/c.Extole_EC_Error_ObjectRequired';
import LABEL_TOOLTIP_TRIGGER_OBJECT from '@salesforce/label/c.Extole_EC_Tooltip_TriggerObject';
import LABEL_TOOLTIP_TRIGGER_CONDITION from '@salesforce/label/c.Extole_EC_Tooltip_TriggerCondition';
import LABEL_TOOLTIP_EVENT_NAME from '@salesforce/label/c.Extole_EC_Tooltip_EventName';

// Preset definitions — Custom first (it's the default state)
const PRESETS = [
    {
        id: 'custom',
        label: LABEL_PRESET_CUSTOM,
        description: LABEL_PRESET_CUSTOM_DESC,
        triggerObject: null,
        triggerType: '',
        triggerField: null,
        triggerValue: null,
        triggerFromValue: null,
        triggerToValue: null,
        eventName: 'sfdc_event',
        defaultParams: []
    },
    {
        id: 'lead_created',
        label: LABEL_PRESET_LEAD_CREATED,
        description: LABEL_PRESET_LEAD_CREATED_DESC,
        triggerObject: 'Lead',
        triggerType: 'CREATED',
        triggerField: null,
        triggerValue: null,
        triggerFromValue: null,
        triggerToValue: null,
        eventName: 'lead_created',
        defaultParams: [
            { paramName: 'email',         field: 'Email' },
            { paramName: 'first_name',    field: 'FirstName' },
            { paramName: 'last_name',     field: 'LastName' },
            { paramName: 'lead_id',       field: 'Id' },
            { paramName: 'advocate_code', field: null }
        ]
    },
    {
        id: 'lead_converted',
        label: LABEL_PRESET_LEAD_CONVERTED,
        description: LABEL_PRESET_LEAD_CONVERTED_DESC,
        triggerObject: 'Lead',
        triggerType: 'FIELD_EQUALS',
        triggerField: 'IsConverted',
        triggerValue: 'true',
        triggerFromValue: null,
        triggerToValue: null,
        eventName: 'lead_converted',
        defaultParams: [
            { paramName: 'email',         field: 'Email' },
            { paramName: 'first_name',    field: 'FirstName' },
            { paramName: 'last_name',     field: 'LastName' },
            { paramName: 'lead_id',       field: 'Id' },
            { paramName: 'advocate_code', field: null }
        ]
    },
    {
        id: 'opportunity_closedwon',
        label: LABEL_PRESET_OPP_WON,
        description: LABEL_PRESET_OPP_WON_DESC,
        triggerObject: 'Opportunity',
        triggerType: 'FIELD_EQUALS',
        triggerField: 'StageName',
        triggerValue: null,
        triggerFromValue: null,
        triggerToValue: null,
        eventName: 'opportunity_closedwon',
        defaultParams: [
            { paramName: 'opportunity_id', field: 'Id' },
            { paramName: 'amount',         field: 'Amount' },
            { paramName: 'close_date',     field: 'CloseDate' }
        ]
    },
];

const POLL_INTERVAL_MS = 2000;
const POLL_MAX_ATTEMPTS = 20;

export default class ExtoleEventModal extends LightningElement {
    @api config = null; // null = add mode, object = edit mode

    @track modalStep = 1; // 1 | 2 | 3
    @track savedConfigKey = null; // set after saveEventConfig on step 2→3

    // Step 1 state
    @track allObjects = [];
    @track objectSearchTerm = '';
    @track isLoadingObjects = false;
    @track selectedObject = null;
    @track triggerType = '';
    @track triggerField = null;
    @track triggerValue = '';
    @track triggerFromValue = '';
    @track triggerToValue = '';
    @track triggerFieldPicklistValues = [];
    @track selectedPresetId = 'custom';
    @track step1Error = null;

    // Step 2 state
    @track availableFields = [];
    @track isLoadingFields = false;
    @track eventName = '';
    @track params = []; // [{ id, paramName, useStatic, field, staticVal }]
    @track step2Error = null;
    @track eventNameError = null;
    @track eventNameAdjusted = false;
    @track isEditLoading = false;

    // Step 3 state
    @track testRecordId = '';
    @track isPreviewLoading = false;
    @track previewPayloadJson = null;
    @track previewError = null;
    @track isDeploying = false;
    @track deployError = null;
    @track deploySuccess = false;
    @track diffRows = []; // [{ key, type ('added'|'removed'|'changed'), oldVal, newVal }]
    @track showTriggerChangedNote = false;

    // Labels
    labelCancel = LABEL_CANCEL;
    labelNext = LABEL_NEXT;
    labelBack = LABEL_BACK;
    labelTriggerObject = LABEL_TRIGGER_OBJECT;
    labelTriggerObjectPh = LABEL_TRIGGER_OBJECT_PH;
    labelTriggerCondition = LABEL_TRIGGER_CONDITION;
    labelTriggerField = LABEL_TRIGGER_FIELD;
    labelTriggerValue = LABEL_TRIGGER_VALUE;
    labelTriggerFrom = LABEL_TRIGGER_FROM;
    labelTriggerTo = LABEL_TRIGGER_TO;
    labelPresetSection = LABEL_PRESET_SECTION;
    labelEventName = LABEL_EVENT_NAME;
    labelEventNameTooltip = LABEL_EVENT_NAME_TOOLTIP;
    labelAppTypeNote = LABEL_APP_TYPE_NOTE;
    labelNullNote = LABEL_NULL_NOTE;
    labelParamName = LABEL_PARAM_NAME;
    labelParamValue = LABEL_PARAM_VALUE;
    labelAddParam = LABEL_ADD_PARAM;
    labelRemoveParam = LABEL_REMOVE_PARAM;
    labelStaticValue = LABEL_STATIC_VALUE;
    labelSfdcField = LABEL_SFDC_FIELD;
    labelFieldPicker = LABEL_FIELD_PICKER;
    labelStaticValueInput = LABEL_STATIC_VALUE_INPUT;
    labelReviewSummary = LABEL_REVIEW_SUMMARY;
    labelReviewObject = LABEL_REVIEW_OBJECT;
    labelReviewTrigger = LABEL_REVIEW_TRIGGER;
    labelReviewEventName = LABEL_REVIEW_EVENT_NAME;
    labelReviewMappings = LABEL_REVIEW_MAPPINGS;
    labelReviewArtifacts = LABEL_REVIEW_ARTIFACTS;
    labelReviewApex = LABEL_REVIEW_APEX;
    labelReviewFlow = LABEL_REVIEW_FLOW;
    labelReviewArtifactsNote = LABEL_REVIEW_ARTIFACTS_NOTE;
    labelReviewTestRecord = LABEL_REVIEW_TEST_RECORD;
    labelReviewTestDesc = LABEL_REVIEW_TEST_DESC;
    labelReviewTestButton = LABEL_REVIEW_TEST_BUTTON;
    labelReviewDeploy = LABEL_REVIEW_DEPLOY;
    labelReviewDeploying = LABEL_REVIEW_DEPLOYING;
    labelReviewDeploySuccess = LABEL_REVIEW_DEPLOY_SUCCESS;
    labelReviewDeployFailed = LABEL_REVIEW_DEPLOY_FAILED;
    labelReviewDiffSection = LABEL_REVIEW_DIFF_SECTION;
    labelReviewDiffNote = LABEL_REVIEW_DIFF_NOTE;
    labelReviewDiffAdded = LABEL_REVIEW_DIFF_ADDED;
    labelReviewDiffRemoved = LABEL_REVIEW_DIFF_REMOVED;
    labelReviewDiffChanged = LABEL_REVIEW_DIFF_CHANGED;
    labelReviewRecordId = LABEL_REVIEW_RECORD_ID;
    labelReviewPayloadPreview = LABEL_REVIEW_PAYLOAD_PREVIEW;
    labelReviewTriggerChanged = LABEL_REVIEW_TRIGGER_CHANGED;
    labelTooltipTriggerObject = LABEL_TOOLTIP_TRIGGER_OBJECT;
    labelTooltipTriggerCondition = LABEL_TOOLTIP_TRIGGER_CONDITION;
    labelTooltipEventName = LABEL_TOOLTIP_EVENT_NAME;

    // ── Lifecycle ──────────────────────────────────────────────────────────

    connectedCallback() {
        this.savedConfigKey = null;
        if (this.config) {
            this.initEditMode();
            this.isEditLoading = true;
            this.loadFields().then(() => {
                // After fields load, also load picklist values if the trigger field is a picklist
                if (this.triggerField && this.isPicklistField) {
                    return getPicklistValues({ objectApiName: this.selectedObject, fieldApiName: this.triggerField })
                        .then(raw => {
                            const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
                            this.triggerFieldPicklistValues = parsed || [];
                        })
                        .catch(() => { this.triggerFieldPicklistValues = []; });
                }
                return Promise.resolve();
            }).then(() => {
                this.isEditLoading = false;
            }).catch(() => {
                this.isEditLoading = false;
            });
        } else {
            this.modalStep = 1;
        }
        this.loadObjects();
        document.body.style.overflow = 'hidden';
    }

    disconnectedCallback() {
        document.body.style.overflow = '';
    }

    initEditMode() {
        const c = this.config;
        this.modalStep = 1;
        this.selectedObject = c.Trigger_Object__c || null;
        this.triggerType = c.Trigger_Type__c || 'CREATED';
        this.triggerField = c.Trigger_Field__c || null;
        this.triggerValue = c.Trigger_Value__c || '';
        this.triggerFromValue = c.Trigger_From_Value__c || '';
        this.triggerToValue = c.Trigger_To_Value__c || '';
        this.eventName = c.Event_Name__c || '';

        // Parse saved field mappings into flat params list
        let mappings = [];
        if (c.Field_Mappings_JSON__c) {
            try {
                mappings = JSON.parse(c.Field_Mappings_JSON__c);
            } catch (e) {
                mappings = [];
            }
        }
        this.params = mappings.map((m, i) => ({
            id: 'p_' + i,
            paramName: m.extole_param || '',
            useStatic: !!m.static_value,
            field: m.sfdc_field || null,
            staticVal: m.static_value || ''
        }));
    }

    // ── Computed getters ───────────────────────────────────────────────────

    get isEditMode() {
        return !!this.config;
    }

    get modalTitle() {
        if (this.isEditMode) return LABEL_EDIT_TITLE;
        if (this.modalStep === 1) return LABEL_STEP1_TITLE;
        if (this.modalStep === 2) return LABEL_STEP2_TITLE;
        return LABEL_STEP3_TITLE;
    }

    get isStep1() { return this.modalStep === 1; }
    get isStep2() { return this.modalStep === 2; }
    get isStep3() { return this.modalStep === 3; }

    get step1Class() { return 'step-indicator-item' + (this.modalStep === 1 ? ' step-active' : ' step-done'); }
    get step2Class() {
        if (this.modalStep < 2) return 'step-indicator-item';
        if (this.modalStep === 2) return 'step-indicator-item step-active';
        return 'step-indicator-item step-done';
    }
    get step3Class() {
        if (this.modalStep < 3) return 'step-indicator-item';
        return 'step-indicator-item step-active';
    }

    get presets() {
        return PRESETS.map(p => ({
            ...p,
            cardClass: 'preset-card' + (this.selectedPresetId === p.id ? ' preset-card-selected' : '')
        }));
    }

    get triggerConditionOptions() {
        return [
            { label: 'Field Changes From → To', value: 'FIELD_CHANGES' },
            { label: 'Field Set To Value', value: 'FIELD_EQUALS' },
            { label: 'Record Created', value: 'CREATED' },
            { label: 'Record Updated', value: 'UPDATED' }
        ].map(opt => {
            // Re-use translation labels
            const map = {
                'CREATED': 'Record Created',
                'UPDATED': 'Record Updated',
                'FIELD_EQUALS': 'Field Set To Value',
                'FIELD_CHANGES': 'Field Changes From → To'
            };
            return { label: map[opt.value], value: opt.value };
        });
    }

    get showFieldPicker() {
        return this.triggerType === 'FIELD_EQUALS' || this.triggerType === 'FIELD_CHANGES';
    }

    get showValueInput() {
        return this.triggerType === 'FIELD_EQUALS' && !!this.triggerField;
    }

    get showFromToInputs() {
        return this.triggerType === 'FIELD_CHANGES' && !!this.triggerField;
    }

    get isObjectLocked() {
        const preset = PRESETS.find(p => p.id === this.selectedPresetId);
        return !!(preset && preset.triggerObject);
    }

    get lockedObjectLabel() {
        if (!this.selectedObject) return '';
        const obj = this.allObjects.find(o => o.value === this.selectedObject);
        return obj ? obj.label : this.selectedObject;
    }

    get isTriggerTypeLocked() {
        const preset = PRESETS.find(p => p.id === this.selectedPresetId);
        return !!(preset && preset.triggerType);
    }

    get lockedTriggerTypeLabel() {
        const opt = this.triggerConditionOptions.find(o => o.value === this.triggerType);
        return opt ? opt.label : this.triggerType;
    }

    get isTriggerFieldLocked() {
        const preset = PRESETS.find(p => p.id === this.selectedPresetId);
        return !!(preset && preset.triggerField);
    }

    get lockedTriggerFieldLabel() {
        if (!this.triggerField) return '';
        const field = this.availableFields.find(f => f.apiName === this.triggerField);
        return field ? field.label : this.triggerField;
    }

    get isTriggerValueLocked() {
        const preset = PRESETS.find(p => p.id === this.selectedPresetId);
        return !!(preset && preset.triggerValue);
    }

    get filteredObjects() {
        const term = (this.objectSearchTerm || '').toLowerCase();
        if (!term) return this.allObjects;
        return this.allObjects.filter(o =>
            o.label.toLowerCase().includes(term) || o.value.toLowerCase().includes(term)
        );
    }

    get fieldOptions() {
        return this.availableFields.map(f => ({ label: f.label, value: f.apiName }));
    }

    get triggerFieldOptions() {
        // Only simple (non-related) fields for trigger condition
        return this.availableFields
            .filter(f => !f.apiName.includes('.'))
            .map(f => ({ label: f.label, value: f.apiName }));
    }

    get isPicklistField() {
        if (!this.triggerField) return false;
        const field = this.availableFields.find(f => f.apiName === this.triggerField);
        return field && (field.type === 'PICKLIST' || field.type === 'MULTIPICKLIST');
    }

    get triggerFieldPicklistOptions() {
        return this.triggerFieldPicklistValues;
    }

    get reviewTriggerLabel() {
        const obj = this.selectedObject || '';
        const type = this.triggerType;
        if (type === 'CREATED') return `${obj} — Record Created`;
        if (type === 'UPDATED') return `${obj} — Record Updated`;
        if (type === 'FIELD_EQUALS') return `${obj} — ${this.triggerField || 'Field'} set to ${this.triggerValue}`;
        if (type === 'FIELD_CHANGES') return `${obj} — ${this.triggerField || 'Field'}: ${this.triggerFromValue || '*'} → ${this.triggerToValue || '*'}`;
        return obj;
    }

    get reviewMappingsTable() {
        const rows = this.params.map(p => ({
            param: p.paramName || '(unnamed)',
            value: p.useStatic ? `"${p.staticVal}" (static)` : (p.field || '(unmapped)')
        }));
        rows.push({ param: 'app_type', value: 'salesforce_crm (auto)' });
        return rows;
    }

    get generatedApexName() {
        return 'ExtoleUniversalHandler';
    }

    get generatedFlowName() {
        if (this.config && this.config.Flow_Name__c) return this.config.Flow_Name__c;
        const key = this.buildConfigKey();
        return `Extole_Flow_${key}`;
    }

    buildConfigKey() {
        if (this.config && this.config.Config_Key__c) return this.config.Config_Key__c;
        return (this.eventName || 'event').replace(/[^a-zA-Z0-9]/g, '_').toLowerCase();
    }

    get hasDiffRows() {
        return this.diffRows && this.diffRows.length > 0;
    }

    get isNextStep1Disabled() {
        if (this.isEditLoading) return true;
        if (!this.selectedObject || !this.triggerType) return true;
        if (this.showValueInput && !this.triggerValue) return true;
        if (this.showFieldPicker && !this.triggerField) return true;
        return false;
    }

    get isNextStep2Disabled() {
        if (!this.eventName) return true;
        // Block if any row is partially filled (name without mapping, or mapping without name)
        return this.params.some(p => {
            const hasName = !!p.paramName;
            const hasMapping = p.useStatic ? !!p.staticVal : !!p.field;
            return hasName !== hasMapping; // XOR — one side filled, other not
        });
    }

    get isDeployDisabled() {
        return this.isDeploying || this.deploySuccess;
    }

    get isPreviewDisabled() {
        return !this.testRecordId || this.isPreviewLoading;
    }

    get hasPreviewPayload() {
        return !!this.previewPayloadJson;
    }

    // ── Step 1: Objects & Trigger ──────────────────────────────────────────

    async loadObjects() {
        this.isLoadingObjects = true;
        try {
            const raw = await getAvailableObjects();
            const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
            // Apex returns {label, apiName, isCustom} — normalize to {label, value, isCommon}
            const normalized = (parsed || []).map(o => ({
                label: o.label,
                value: o.apiName,
                isCommon: !o.isCustom
            }));
            const common = normalized.filter(o => o.isCommon);
            const others = normalized.filter(o => !o.isCommon).sort((a, b) => a.label.localeCompare(b.label));
            this.allObjects = [...common, ...others];
        } catch (error) {
            this.showError(LABEL_ERROR_LOAD_OBJECTS, error);
        } finally {
            this.isLoadingObjects = false;
        }
    }

    handleObjectSearch(event) {
        this.objectSearchTerm = event.target.value;
    }

    handleObjectSelect(event) {
        const val = event.detail.value;
        if (val !== this.selectedObject) {
            this.selectedObject = val;
            this.triggerField = null;
            this.availableFields = [];
            this.loadFields();
        }
    }

    handleTriggerTypeChange(event) {
        this.triggerType = event.detail.value;
    }

    handleTriggerFieldChange(event) {
        this.triggerField = event.detail.value;
        this.triggerValue = '';
        this.triggerFromValue = '';
        this.triggerToValue = '';
        this.triggerFieldPicklistValues = [];
        if (this.isPicklistField) {
            getPicklistValues({ objectApiName: this.selectedObject, fieldApiName: this.triggerField })
                .then(raw => {
                    const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
                    this.triggerFieldPicklistValues = parsed || [];
                })
                .catch(() => { this.triggerFieldPicklistValues = []; });
        }
    }

    handleTriggerValueChange(event) {
        this.triggerValue = event.detail ? event.detail.value : event.target.value;
    }

    handleTriggerFromChange(event) {
        this.triggerFromValue = event.detail ? event.detail.value : event.target.value;
    }

    handleTriggerToChange(event) {
        this.triggerToValue = event.detail ? event.detail.value : event.target.value;
    }

    handlePresetSelect(event) {
        const presetId = event.currentTarget.dataset.presetId;
        const preset = PRESETS.find(p => p.id === presetId);
        if (!preset) return;

        this.selectedPresetId = presetId;
        this.selectedObject = preset.triggerObject || null;
        this.triggerType = preset.triggerType;
        this.triggerField = preset.triggerField;
        this.triggerValue = preset.triggerValue || '';
        this.triggerFromValue = preset.triggerFromValue || '';
        this.triggerToValue = preset.triggerToValue || '';
        this.eventName = preset.eventName || '';

        this.params = (preset.defaultParams || []).map((p, i) => ({
            id: 'p_' + i,
            paramName: p.paramName,
            useStatic: false,
            field: p.field || null,
            staticVal: ''
        }));

        // Clear stale field data when object changes
        this.availableFields = [];
        this.triggerFieldPicklistValues = [];

        if (preset.triggerObject) {
            this.loadFields();
        }
    }

    // ── Step 2: Field Mappings ─────────────────────────────────────────────

    async loadFields() {
        if (!this.selectedObject) return;
        this.isLoadingFields = true;
        try {
            const raw = await getFieldsForObject({ objectApiName: this.selectedObject });
            const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
            this.availableFields = parsed || [];

            // Auto-load picklist values if a trigger field is already set and is a picklist
            if (this.triggerField && this.triggerFieldPicklistValues.length === 0) {
                const field = this.availableFields.find(f => f.apiName === this.triggerField);
                if (field && (field.type === 'PICKLIST' || field.type === 'MULTIPICKLIST')) {
                    getPicklistValues({ objectApiName: this.selectedObject, fieldApiName: this.triggerField })
                        .then(raw => {
                            const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
                            this.triggerFieldPicklistValues = parsed || [];
                        })
                        .catch(() => {});
                }
            }
        } catch (error) {
            this.showError(LABEL_ERROR_LOAD_FIELDS, error);
        } finally {
            this.isLoadingFields = false;
        }
    }

    handleEventNameChange(event) {
        this.eventName = event.target.value;
        this.eventNameError = null;
        this.eventNameAdjusted = false;
    }

    // Parameters
    handleAddParam() {
        const newId = 'p_' + Date.now();
        this.params = [
            ...this.params,
            { id: newId, paramName: '', useStatic: false, field: null, staticVal: '' }
        ];
        // Scroll modal body to reveal the new row after LWC renders + browser paints
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            requestAnimationFrame(() => {
                const body = this.template.querySelector('.modal-body');
                if (body) body.scrollTo({ top: body.scrollHeight, behavior: 'smooth' });
            });
        }, 0);
    }

    handleRemoveParam(event) {
        const id = event.currentTarget.dataset.paramId;
        this.params = this.params.filter(p => p.id !== id);
    }

    // Use blur instead of change so the reactive array isn't mutated on every
    // keystroke, which would trigger re-renders and cause visible input lag.
    handleParamNameBlur(event) {
        const id = event.currentTarget.dataset.paramId;
        const param = this.params.find(p => p.id === id);
        if (param) param.paramName = event.target.value;
    }

    handleParamFieldChange(event) {
        const id = event.currentTarget.dataset.paramId;
        this.params = this.params.map(p =>
            p.id === id ? { ...p, field: event.detail.value } : p
        );
    }

    handleParamStaticToggle(event) {
        const id = event.currentTarget.dataset.paramId;
        const param = this.params.find(p => p.id === id);
        if (param) param.useStatic = event.target.checked;
    }

    handleParamStaticValueChange(event) {
        const id = event.currentTarget.dataset.paramId;
        const param = this.params.find(p => p.id === id);
        if (param) param.staticVal = event.target.value;
    }

    // ── Step 3: Review & Deploy ────────────────────────────────────────────

    buildDiff() {
        if (!this.isEditMode || !this.config) {
            this.diffRows = [];
            this.showTriggerChangedNote = false;
            return;
        }

        // Check trigger condition change
        const oldTriggerKey = `${this.config.Trigger_Object__c}|${this.config.Trigger_Type__c}|${this.config.Trigger_Field__c}|${this.config.Trigger_Value__c}`;
        const newTriggerKey = `${this.selectedObject}|${this.triggerType}|${this.triggerField}|${this.triggerValue}`;
        this.showTriggerChangedNote = oldTriggerKey !== newTriggerKey;

        // Build old and new payload key maps
        let oldMappings = [];
        if (this.config.Field_Mappings_JSON__c) {
            try { oldMappings = JSON.parse(this.config.Field_Mappings_JSON__c); } catch (e) { oldMappings = []; }
        }

        const oldMap = {};
        oldMappings.forEach(m => { oldMap[m.extole_param] = m.sfdc_field || m.static_value; });
        oldMap['app_type'] = 'salesforce_crm';
        if (this.config.Event_Name__c) oldMap['__event_name'] = this.config.Event_Name__c;

        const newMap = {};
        this.params.forEach(p => {
            if (p.paramName) {
                newMap[p.paramName] = p.useStatic ? p.staticVal : p.field;
            }
        });
        newMap['app_type'] = 'salesforce_crm';
        newMap['__event_name'] = this.eventName;

        const rows = [];
        const allKeys = new Set([...Object.keys(oldMap), ...Object.keys(newMap)]);
        allKeys.forEach(key => {
            const oldVal = oldMap[key];
            const newVal = newMap[key];
            if (oldVal === undefined) {
                rows.push({ key, type: 'added', isAdded: true, isRemoved: false, isChanged: false, oldVal: '', newVal: newVal || '' });
            } else if (newVal === undefined) {
                rows.push({ key, type: 'removed', isAdded: false, isRemoved: true, isChanged: false, oldVal: oldVal || '', newVal: '' });
            } else if (oldVal !== newVal) {
                rows.push({ key, type: 'changed', isAdded: false, isRemoved: false, isChanged: true, oldVal: oldVal || '', newVal: newVal || '' });
            }
        });
        this.diffRows = rows;
    }

    handleTestRecordIdChange(event) {
        this.testRecordId = event.target.value;
        this.previewPayloadJson = null;
        this.previewError = null;
    }

    async handlePreviewPayload() {
        if (!this.testRecordId) return;
        this.isPreviewLoading = true;
        this.previewPayloadJson = null;
        this.previewError = null;
        try {
            const configData = this.buildConfigPayload();
            const result = await previewPayload({
                configJson: JSON.stringify(configData),
                recordId: this.testRecordId
            });
            const parsed = typeof result === 'string' ? JSON.parse(result) : result;
            this.previewPayloadJson = JSON.stringify(parsed, null, 2);
        } catch (error) {
            this.previewError = (error && error.body && error.body.message) || LABEL_ERROR_PREVIEW;
        } finally {
            this.isPreviewLoading = false;
        }
    }

    buildConfigPayload() {
        const mappings = [];
        this.params.forEach(p => {
            if (p.paramName) {
                mappings.push({
                    extole_param: p.paramName,
                    sfdc_field: p.useStatic ? null : p.field,
                    static_value: p.useStatic ? p.staticVal : null
                });
            }
        });

        return {
            configKey: this.isEditMode ? this.config.Config_Key__c : (this.savedConfigKey || null),
            eventName: this.eventName,
            triggerObject: this.selectedObject,
            triggerType: this.triggerType,
            triggerField: this.triggerField,
            triggerValue: this.triggerValue,
            triggerFromValue: this.triggerFromValue,
            triggerToValue: this.triggerToValue,
            fieldMappingsJson: JSON.stringify(mappings)
        };
    }

    async handleDeploy() {
        this.isDeploying = true;
        this.deployError = null;
        this.deploySuccess = false;
        try {
            const configData = this.buildConfigPayload();
            const jobId = await deployEventConfig({ configJson: JSON.stringify(configData) });
            await this.pollUntilDone(jobId);
        } catch (error) {
            this.deployError = (error && error.body && error.body.message)
                ? `${LABEL_REVIEW_DEPLOY_FAILED} ${error.body.message}`
                : LABEL_REVIEW_DEPLOY_FAILED;
            this.isDeploying = false;
        }
    }

    async pollUntilDone(jobId) {
        let attempts = 0;
        const poll = async () => {
            attempts++;
            try {
                const status = await pollDeployStatus({ jobId });
                const parsed = typeof status === 'string' ? JSON.parse(status) : status;
                if (parsed.status === 'SUCCEEDED') {
                    this.deploySuccess = true;
                    this.isDeploying = false;
                    this.showSuccess(LABEL_REVIEW_DEPLOY_SUCCESS);
                    this.dispatchEvent(new CustomEvent('deployed'));
                } else if (parsed.status === 'FAILED') {
                    this.deployError = `${LABEL_REVIEW_DEPLOY_FAILED} ${parsed.errorMessage || ''}`;
                    this.isDeploying = false;
                } else if (attempts < POLL_MAX_ATTEMPTS) {
                    // Still pending — poll again
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    setTimeout(poll, POLL_INTERVAL_MS);
                } else {
                    this.deployError = 'Deployment timed out. Check Setup → Apex Jobs for status.';
                    this.isDeploying = false;
                }
            } catch (error) {
                this.deployError = (error && error.body && error.body.message) || 'Deployment polling failed.';
                this.isDeploying = false;
            }
        };
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(poll, POLL_INTERVAL_MS);
    }

    // ── Navigation ─────────────────────────────────────────────────────────

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleNext() {
        this.step1Error = null;
        if (this.modalStep === 1) {
            if (!this.selectedObject) {
                this.step1Error = LABEL_ERROR_OBJECT_REQUIRED;
                return;
            }
            await this.loadFields();
            // Auto-increment default event name if already taken (only on first entry — not after Back from step 3)
            this.eventNameAdjusted = false;
            if (!this.isEditMode && this.eventName && !this.savedConfigKey) {
                try {
                    const original = this.eventName;
                    const suggested = await suggestUniqueEventName({ baseEventName: this.eventName, excludeConfigKey: null });
                    if (suggested !== original) {
                        this.eventName = suggested;
                        // Only warn if the user typed their own name — not for preset-generated names
                        this.eventNameAdjusted = this.selectedPresetId === 'custom';
                    }
                } catch (e) {
                    // Non-fatal — skip suggestion on error
                }
            }
            this.modalStep = 2;
        } else if (this.modalStep === 2) {
            if (!this.eventName) {
                this.step2Error = LABEL_ERROR_EVENT_NAME_REQUIRED;
                return;
            }
            // Validate event name uniqueness — exclude the config already saved in this session
            const excludeKey = this.isEditMode ? this.config.Config_Key__c : (this.savedConfigKey || null);
            try {
                const suggested = await suggestUniqueEventName({ baseEventName: this.eventName, excludeConfigKey: excludeKey });
                if (suggested !== this.eventName) {
                    this.eventNameError = LABEL_ERROR_EVENT_NAME_DUPLICATE + ' Try: ' + suggested;
                    return;
                }
            } catch (e) {
                // Non-fatal — allow proceed if check fails
            }
            this.eventNameError = null;
            this.step2Error = null;
            try {
                const configData = this.buildConfigPayload();
                const key = await saveEventConfig({ configJson: JSON.stringify(configData) });
                this.savedConfigKey = key;
            } catch (e) {
                // Non-fatal — draft save failure should not block the wizard
                console.error('saveEventConfig failed:', e);
            }
            this.buildDiff();
            this.modalStep = 3;
        }
    }

    handleBack() {
        if (this.modalStep === 2) {
            this.modalStep = 1;
            this.eventNameError = null;
            this.eventNameAdjusted = false;
        } else if (this.modalStep === 3) {
            this.modalStep = 2;
            this.previewPayloadJson = null;
            this.previewError = null;
            this.deployError = null;
            this.deploySuccess = false;
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
