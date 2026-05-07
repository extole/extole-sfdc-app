import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSettings from '@salesforce/apex/ExtoleController.getSettings';
import saveSettings from '@salesforce/apex/ExtoleController.saveSettings';
import getObjectFields from '@salesforce/apex/ExtoleController.getObjectFields';
import getFieldValues from '@salesforce/apex/ExtoleController.getFieldValues';

import LABEL_LIST_VIEW_SECTION from '@salesforce/label/c.Extole_Settings_ListView_Section';
import LABEL_SHOW_LIST_VIEW from '@salesforce/label/c.Extole_Settings_ShowListView';
import LABEL_LEAD_FIELD from '@salesforce/label/c.Extole_Settings_ListView_Field';
import LABEL_LEAD_VALUE from '@salesforce/label/c.Extole_Settings_ListView_Value';
import LABEL_TRACKING_START from '@salesforce/label/c.Extole_Settings_ListView_StartDate';
import LABEL_SAVE_SETTINGS from '@salesforce/label/c.Extole_Settings_SaveSettings';
import LABEL_SETTINGS_SAVED from '@salesforce/label/c.Extole_Success_SettingsSaved';
import LABEL_TOOLTIP_SECTION_LIST_VIEW from '@salesforce/label/c.Extole_Tooltip_Section_ListView';

const ATTRIBUTION_COLUMN_DEFAULTS = {
    Contact:     ['Account.Name', 'Email', 'Title'],
    Lead:        ['Email', 'Company', 'Status'],
    Opportunity: ['Account.Name', 'StageName', 'Amount']
};

const DEFAULT_SETTINGS = {
    Show_List_View__c: false,
    List_View_Object__c: 'Contact',
    List_View_Field__c: '',
    List_View_Value__c: '',
    List_View_Columns__c: '',
    List_View_Start_Date__c: null
};

export default class ExtoleManageListView extends LightningElement {
    @track settings = { ...DEFAULT_SETTINGS };
    @track hasDirtySettings = false;
    @track isSaving = false;

    @track attributionObjectOptions = [
        { label: 'Contact',     value: 'Contact'     },
        { label: 'Lead',        value: 'Lead'        },
        { label: 'Opportunity', value: 'Opportunity' }
    ];
    @track attributionFieldOptions = [];
    @track attributionValueOptions = [];
    @track isLoadingAttributionFields = false;
    @track isLoadingAttributionValues = false;

    labelListViewSection = LABEL_LIST_VIEW_SECTION;
    labelShowListView = LABEL_SHOW_LIST_VIEW;
    labelLeadField = LABEL_LEAD_FIELD;
    labelLeadValue = LABEL_LEAD_VALUE;
    labelTrackingStart = LABEL_TRACKING_START;
    labelSaveSettings = LABEL_SAVE_SETTINGS;
    tooltipSectionListView = LABEL_TOOLTIP_SECTION_LIST_VIEW;

    connectedCallback() {
        this.loadAll();
    }

    async loadAll() {
        await this.loadSettings();
        await this.loadAttributionFields();
        if (this.settings.List_View_Field__c) {
            await this.loadAttributionValues();
        }
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

    get selectedAttributionColumns() {
        const saved = this.settings.List_View_Columns__c;
        if (saved) return saved.split(',').map(s => s.trim()).filter(Boolean);
        const obj = this.settings.List_View_Object__c || 'Contact';
        return ATTRIBUTION_COLUMN_DEFAULTS[obj] || ATTRIBUTION_COLUMN_DEFAULTS.Contact;
    }

    get isValueDisabled() {
        return this.isLoadingAttributionValues || !this.settings.List_View_Field__c;
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

    handleAttributionColumnsChange(event) {
        this.settings = {
            ...this.settings,
            List_View_Columns__c: event.detail.value.join(',')
        };
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
            this.showSuccess(LABEL_SETTINGS_SAVED);
        } catch (error) {
            this.showError('Failed to save settings.', error);
        } finally {
            this.isSaving = false;
        }
    }

    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message, variant: 'success' }));
    }

    showError(message, error) {
        const detail = error && error.body && error.body.message ? error.body.message : '';
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: detail || message, variant: 'error' }));
    }
}
