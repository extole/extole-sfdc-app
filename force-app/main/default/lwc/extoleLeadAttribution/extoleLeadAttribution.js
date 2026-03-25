import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSettings from '@salesforce/apex/ExtoleController.getSettings';
import getSnapshots from '@salesforce/apex/ExtoleController.getSnapshots';

import LABEL_TITLE from '@salesforce/label/c.Extole_LeadAttribution_Title';
import LABEL_NO_LEADS from '@salesforce/label/c.Extole_LeadAttribution_NoLeads';
import LABEL_TRACKING_SINCE from '@salesforce/label/c.Extole_LeadAttribution_TrackingSince';
import LABEL_RAF_LEADS from '@salesforce/label/c.Extole_LeadAttribution_RAFLeads';
import LABEL_CONVERSION_RATE from '@salesforce/label/c.Extole_LeadAttribution_ConversionRate';
import LABEL_PIPELINE_VALUE from '@salesforce/label/c.Extole_LeadAttribution_PipelineValue';
import LABEL_DISABLED from '@salesforce/label/c.Extole_LeadAttribution_Disabled';

// Snapshot report names that map to lead attribution metrics
const RAF_LEADS_REPORT = 'raf_leads_created';
const RAF_CONVERSION_REPORT = 'raf_lead_conversion_rate';
const PIPELINE_REPORT = 'raf_pipeline_value';

export default class ExtoleLeadAttribution extends LightningElement {
    @track settings = null;
    @track snapshots = [];
    @track isLoading = true;

    labelTitle = LABEL_TITLE;
    labelNoLeads = LABEL_NO_LEADS;
    labelTrackingSince = LABEL_TRACKING_SINCE;
    labelRAFLeads = LABEL_RAF_LEADS;
    labelConversionRate = LABEL_CONVERSION_RATE;
    labelPipelineValue = LABEL_PIPELINE_VALUE;
    labelDisabled = LABEL_DISABLED;

    connectedCallback() {
        this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        try {
            const [settingsResult, snapshotsResult] = await Promise.all([
                getSettings(),
                getSnapshots()
            ]);
            this.settings = settingsResult;
            this.snapshots = snapshotsResult || [];
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Failed to load lead attribution data.',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    get isDisabled() {
        return !this.settings || !this.settings.Show_Lead_Attribution__c;
    }

    get hasData() {
        return this.rafLeadCount !== null || this.conversionRate !== null || this.pipelineValue !== null;
    }

    get trackingSinceText() {
        if (!this.settings || !this.settings.RAF_Tracking_Start_Date__c) return null;
        return `${LABEL_TRACKING_SINCE} ${this.settings.RAF_Tracking_Start_Date__c}`;
    }

    getSnapshotValue(reportName) {
        const snap = this.snapshots.find(
            s => s.Report_Name__c && s.Report_Name__c.toLowerCase().includes(reportName)
        );
        return snap ? snap.Value__c : null;
    }

    get rafLeadCount() {
        return this.getSnapshotValue(RAF_LEADS_REPORT);
    }

    get conversionRate() {
        return this.getSnapshotValue(RAF_CONVERSION_REPORT);
    }

    get pipelineValue() {
        return this.getSnapshotValue(PIPELINE_REPORT);
    }

    get formattedLeadCount() {
        const val = parseFloat(this.rafLeadCount);
        if (isNaN(val)) return '—';
        return new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(val);
    }

    get formattedConversionRate() {
        const val = parseFloat(this.conversionRate);
        if (isNaN(val)) return '—';
        return `${new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 }).format(val)}%`;
    }

    get formattedPipelineValue() {
        const val = parseFloat(this.pipelineValue);
        if (isNaN(val)) return '—';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            maximumFractionDigits: 0
        }).format(val);
    }
}
