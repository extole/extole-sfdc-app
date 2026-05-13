import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getCardForEmail from '@salesforce/apex/ExtolePersonCardController.getCardForEmail';

import LEAD_EMAIL from '@salesforce/schema/Lead.Email';
import CONTACT_EMAIL from '@salesforce/schema/Contact.Email';

export default class ExtolePersonCard extends LightningElement {
    @api recordId;
    @api objectApiName;

    @track card = null;
    @track isLoading = false;
    @track loadError = null;

    email = null;

    get emailField() {
        return this.objectApiName === 'Lead' ? LEAD_EMAIL : CONTACT_EMAIL;
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$fieldsToFetch' })
    wiredRecord({ data, error }) {
        if (data) {
            this.email = getFieldValue(data, this.emailField);
            if (this.email) {
                this.fetchCard();
            }
        } else if (error) {
            this.loadError = error.body ? error.body.message : 'Unable to read record.';
        }
    }

    get fieldsToFetch() {
        return this.objectApiName === 'Lead' ? [LEAD_EMAIL] : [CONTACT_EMAIL];
    }

    async fetchCard() {
        this.isLoading = true;
        this.loadError = null;
        try {
            this.card = await getCardForEmail({ email: this.email });
        } catch (e) {
            this.loadError = (e && e.body && e.body.message) || 'Failed to load Extole data.';
        } finally {
            this.isLoading = false;
        }
    }

    // ── Computed view state ─────────────────────────────────────────────────

    get shouldRender() {
        // Self-hide: only render the card if there's something to show
        return this.card && this.card.hasAnyData;
    }

    get hasShareLinks() {
        return this.card && this.card.shareLinks && this.card.shareLinks.length > 0;
    }

    get hasFriends() {
        return this.card && this.card.friends && this.card.friends.length > 0;
    }

    get hasRewards() {
        return this.card && this.card.rewards && this.card.rewards.length > 0;
    }

    get hasReferredBy() {
        return this.card && this.card.referredBy != null;
    }

    get headerSubtitle() {
        // Single subtitle that adapts to mode: friend-only, advocate-only, or both
        const advocate = this.hasFriends;
        const friend = this.hasReferredBy;
        if (advocate && friend)  return 'Advocate · referred';
        if (advocate)            return 'Advocate';
        if (friend)              return 'Referred friend';
        return 'Activity';
    }

    get friendsLabel() {
        if (!this.hasFriends) return '';
        const n = this.card.friends.length;
        return `Friends (${n})`;
    }

    get decoratedFriends() {
        if (!this.hasFriends) return [];
        return this.card.friends.map(f => ({
            ...f,
            sfdcUrl: f.sfdcRecordId ? `/lightning/r/${f.sfdcObjectType}/${f.sfdcRecordId}/view` : null,
            isLinked: !!f.sfdcRecordId,
            engagements: (f.engagements || []).map(eng => ({
                ...eng,
                hasMilestones: eng.milestones && eng.milestones.length > 0,
                milestones: (eng.milestones || []).map(m => ({
                    ...m,
                    cssClass: m.completed ? 'milestone milestone-completed' : 'milestone milestone-pending',
                    tooltip: m.completed ? `Completed ${m.eventDate || ''}` : 'Not yet completed'
                }))
            }))
        }));
    }

    get referredByDecorated() {
        if (!this.hasReferredBy) return null;
        const r = this.card.referredBy;
        return {
            ...r,
            sfdcUrl: r.sfdcRecordId ? `/lightning/r/${r.sfdcObjectType}/${r.sfdcRecordId}/view` : null,
            isLinked: !!r.sfdcRecordId
        };
    }

    handleCopyLink(event) {
        const link = event.currentTarget.dataset.link;
        if (!link) return;
        if (navigator && navigator.clipboard) {
            navigator.clipboard.writeText(link);
        }
    }
}
