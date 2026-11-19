import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getOffersData from '@salesforce/apex/ExtolePersonCardController.getOffersData';
import {
    decorateMilestones,
    describeReward,
    programPillStyle,
    OFFERS_HELP_TEXT
} from 'c/extolePersonCardUtils';

import LEAD_EMAIL from '@salesforce/schema/Lead.Email';
import LEAD_NAME from '@salesforce/schema/Lead.Name';
import CONTACT_EMAIL from '@salesforce/schema/Contact.Email';
import CONTACT_NAME from '@salesforce/schema/Contact.Name';

export default class ExtoleOffersCard extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api disabled = false;

    email = null;
    sfdcName = null;
    data = null;
    isLoading = false;
    loadError = null;
    collapsed = {};
    helpText = OFFERS_HELP_TEXT;

    get isAccount() {
        return this.objectApiName === 'Account';
    }

    // Account fields are referenced by string: PersonEmail and IsPersonAccount
    // only exist when Person Accounts is enabled, so they can't be schema imports.
    get requiredFields() {
        if (this.isAccount) return ['Account.Name'];
        return this.objectApiName === 'Lead'
            ? [LEAD_EMAIL, LEAD_NAME]
            : [CONTACT_EMAIL, CONTACT_NAME];
    }

    get optionalFields() {
        return this.isAccount
            ? ['Account.PersonEmail', 'Account.IsPersonAccount']
            : [];
    }

    @wire(getRecord, {
        recordId: '$recordId',
        fields: '$requiredFields',
        optionalFields: '$optionalFields'
    })
    wiredRecord({ data, error }) {
        if (data) {
            if (this.isAccount) {
                const isPerson =
                    data.fields.IsPersonAccount &&
                    data.fields.IsPersonAccount.value;
                if (!isPerson) return;
                this.email = data.fields.PersonEmail
                    ? data.fields.PersonEmail.value
                    : null;
                this.sfdcName = data.fields.Name
                    ? data.fields.Name.value
                    : null;
            } else {
                const isLead = this.objectApiName === 'Lead';
                this.email = getFieldValue(
                    data,
                    isLead ? LEAD_EMAIL : CONTACT_EMAIL
                );
                this.sfdcName = getFieldValue(
                    data,
                    isLead ? LEAD_NAME : CONTACT_NAME
                );
            }
            if (this.email) this.load();
        } else if (error) {
            this.loadError = error.body
                ? error.body.message
                : 'Unable to read record.';
        }
    }

    async load() {
        this.isLoading = true;
        this.loadError = null;
        try {
            this.data = await getOffersData({ email: this.email });
        } catch (e) {
            this.loadError =
                (e && e.body && e.body.message) ||
                'Failed to load Extole offers.';
        } finally {
            this.isLoading = false;
        }
    }

    get showCard() {
        return !this.disabled && this.data && this.data.hasAnyData;
    }

    get displayName() {
        return this.sfdcName || this.email || '';
    }

    // The hover text names whose profile the link opens.
    get viewLinkTitle() {
        return this.displayName
            ? `Open ${this.displayName} in My Extole`
            : 'Open this person in My Extole';
    }

    get profileUrl() {
        return this.data && this.data.profileUrl ? this.data.profileUrl : null;
    }

    // One block per program: the pill, the reward, and the steps.
    get offers() {
        if (!this.data || !this.data.programs) return [];
        return this.data.programs.map((p, i) => {
            const key = `${p.program || 'none'}-${i}`;
            const milestones = decorateMilestones(p.steps);
            const expanded = !this.collapsed[key];
            return {
                key,
                program: p.program,
                programStyle: p.program ? programPillStyle(p.program) : '',
                reward: this.rewardFor(p),
                milestones,
                showMilestones: expanded && milestones.length > 0,
                canToggle: milestones.length > 0,
                chevron: expanded
                    ? 'utility:chevrondown'
                    : 'utility:chevronright'
            };
        });
    }

    // The reward pill, or nothing when there is no amount, reward or decline.
    rewardFor(p) {
        const amounts = this.data && this.data.ownAmounts;
        const r = describeReward(
            { reward: p.reward, status: p.status },
            amounts && amounts[p.program]
        );
        return r.text ? r : null;
    }

    toggleOffer(event) {
        const key = event.currentTarget.dataset.key;
        if (!key) return;
        this.collapsed = { ...this.collapsed, [key]: !this.collapsed[key] };
    }

    stopClick(event) {
        event.stopPropagation();
    }
}
