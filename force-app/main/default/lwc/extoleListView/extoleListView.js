import { LightningElement, track, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAttributedLeads from '@salesforce/apex/ExtoleController.getAttributedLeads';

import LABEL_TITLE from '@salesforce/label/c.Extole_ListView_Title';
import LABEL_TRACKING_SINCE from '@salesforce/label/c.Extole_ListView_TrackingSince';
import LABEL_NO_RECORDS from '@salesforce/label/c.Extole_ListView_NoRecords';
import LABEL_NOT_CONFIGURED from '@salesforce/label/c.Extole_ListView_NotConfigured';
import LABEL_OPEN_IN_SF from '@salesforce/label/c.Extole_ListView_OpenInSalesforce';

export default class ExtoleListView extends NavigationMixin(LightningElement) {
    @track records = [];
    @track isLoading = true;
    @track configured = false;
    @track totalCount = 0;
    @track thisMonthCount = 0;
    @track thisQuarterCount = 0;
    @track objectType = 'Contact';
    @track filterField = '';
    @track filterValue = '';
    @track trackingStart = null;
    @track errorMessage = null;
    @track extraColumns = [];

    get labelTitle() {
        return this.objectType === 'Lead' ? 'Lead List' : 'Contact List';
    }
    labelTrackingSince = LABEL_TRACKING_SINCE;
    labelNoRecords = LABEL_NO_RECORDS;
    labelNotConfigured = LABEL_NOT_CONFIGURED;
    labelOpenInSf = LABEL_OPEN_IN_SF;

    _settingsTimestamp = null;

    @api
    get settingsTimestamp() { return this._settingsTimestamp; }
    set settingsTimestamp(val) {
        if (val && val !== this._settingsTimestamp) {
            this._settingsTimestamp = val;
            this.loadRecords();
        }
    }

    connectedCallback() {
        this.loadRecords();
    }

    @api refresh() {
        this.loadRecords();
    }

    async loadRecords() {
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const result = await getAttributedLeads();
            this.configured       = result.configured       || false;
            this.totalCount       = result.totalCount       || 0;
            this.thisMonthCount   = result.thisMonthCount   || 0;
            this.thisQuarterCount = result.thisQuarterCount || 0;
            this.objectType       = result.objectType       || 'Contact';
            this.filterField      = result.field            || '';
            this.filterValue      = result.value            || '';
            this.trackingStart    = result.startDate        || null;
            this.extraColumns     = result.extraColumns     || [];

            if (result.error) {
                this.errorMessage = result.error;
                this.records = [];
            } else {
                const cols = this.extraColumns;
                this.records = (result.records || []).map(rec => {
                    const row = {
                        ...rec,
                        recordUrl:      `/lightning/r/${this.objectType}/${rec.Id}/view`,
                        ownerName:      rec.Owner ? rec.Owner.Name : '',
                        attrFieldValue: rec[this.filterField] || '',
                        formattedDate:  rec.CreatedDate
                            ? new Intl.DateTimeFormat('en-US', {
                                month: 'short', day: 'numeric', year: 'numeric'
                              }).format(new Date(rec.CreatedDate))
                            : ''
                    };
                    cols.forEach(col => {
                        if (col.fieldName === 'Account.Name') {
                            row[col.flatKey] = rec.Account ? rec.Account.Name : '';
                        } else {
                            row[col.flatKey] = rec[col.fieldName] != null ? String(rec[col.fieldName]) : '';
                        }
                    });
                    return row;
                });
            }
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: (error && error.body && error.body.message) || 'Failed to load records.',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    get columns() {
        const attrLabel = this.filterField || 'Attribution Field';
        const cols = [
            {
                label: 'Name', fieldName: 'recordUrl', type: 'url',
                typeAttributes: { label: { fieldName: 'Name' }, target: '_self' }
            }
        ];
        this.extraColumns.forEach(col => {
            const type = col.fieldName === 'Email' ? 'email' : 'text';
            cols.push({ label: col.label, fieldName: col.flatKey, type });
        });
        cols.push(
            { label: attrLabel, fieldName: 'attrFieldValue', type: 'text', initialWidth: 150 },
            { label: 'Created', fieldName: 'formattedDate', type: 'text', initialWidth: 120 },
            { label: 'Owner', fieldName: 'ownerName', type: 'text', initialWidth: 140 }
        );
        return cols;
    }

    get hasRecords() {
        return this.records && this.records.length > 0;
    }

    get trackingSinceText() {
        if (!this.trackingStart) return null;
        // Parse as local date (not UTC) to avoid timezone-shifting the date back one day
        const [year, month, day] = this.trackingStart.split('-').map(Number);
        return new Intl.DateTimeFormat('en-US', {
            month: 'short', day: 'numeric', year: 'numeric'
        }).format(new Date(year, month - 1, day));
    }

    get filterDescription() {
        if (!this.filterField || !this.filterValue) return '';
        const label = this.filterField.replace(/([A-Z])/g, ' $1').trim();
        return `${label}: ${this.filterValue}`;
    }

    handleOpenInSalesforce() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: this.objectType,
                actionName: 'list'
            }
        });
    }
}
