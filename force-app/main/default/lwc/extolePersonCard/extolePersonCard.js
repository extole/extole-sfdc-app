import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getCardData from '@salesforce/apex/ExtolePersonCardController.getCardData';
import getShareLinkFieldSetting from '@salesforce/apex/ExtoleBackfillController.getShareLinkFieldSetting';

import LEAD_EMAIL from '@salesforce/schema/Lead.Email';
import LEAD_NAME from '@salesforce/schema/Lead.Name';
import CONTACT_EMAIL from '@salesforce/schema/Contact.Email';
import CONTACT_NAME from '@salesforce/schema/Contact.Name';

const PALETTE = [
    { primary: '#1D9E75', fill: 'rgba(29, 158, 117, 0.12)' },
    { primary: '#2563EB', fill: 'rgba(37, 99, 235, 0.10)' },
    { primary: '#8B5CF6', fill: 'rgba(139, 92, 246, 0.10)' },
    { primary: '#F97316', fill: 'rgba(249, 115, 22, 0.12)' },
    { primary: '#E94560', fill: 'rgba(233, 69, 96, 0.10)' }
];

function hashProgram(name) {
    if (!name) return 0;
    let h = 0;
    for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) | 0;
    return Math.abs(h) % PALETTE.length;
}

function programColors(name) {
    return PALETTE[hashProgram(name)];
}

function computeInitials(name) {
    if (!name) return '?';
    const trimmed = String(name).trim();
    if (!trimmed) return '?';
    const parts = trimmed.split(/\s+/);
    if (parts.length >= 2) {
        return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return trimmed.substring(0, 2).toUpperCase();
}

function formatShortDate(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const yy = String(d.getFullYear()).slice(-2);
    return `${mm}/${dd}/${yy}`;
}

export default class ExtolePersonCard extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api disabled = false;

    @track card = null;
    @track isLoading = false;
    @track loadError = null;
    @track sectionCollapsed = {
        shareLinks: false,
        friends: true,
        referredBy: false
    };

    email = null;
    sfdcName = null;
    sfdcShareLink = null;
    @track configuredShareLinkField = null;

    get emailField() {
        return this.objectApiName === 'Lead' ? LEAD_EMAIL : CONTACT_EMAIL;
    }

    get nameField() {
        return this.objectApiName === 'Lead' ? LEAD_NAME : CONTACT_NAME;
    }

    get shareLinkFieldRef() {
        if (!this.configuredShareLinkField) return null;
        return `${this.objectApiName}.${this.configuredShareLinkField}`;
    }

    async connectedCallback() {
        try {
            this.configuredShareLinkField = await getShareLinkFieldSetting({
                objectType: this.objectApiName
            });
        } catch {
            this.configuredShareLinkField = null;
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$fieldsToFetch' })
    wiredRecord({ data, error }) {
        if (data) {
            this.email = getFieldValue(data, this.emailField);
            this.sfdcName = getFieldValue(data, this.nameField);
            const fname = this.configuredShareLinkField;
            this.sfdcShareLink =
                fname && data.fields && data.fields[fname]
                    ? data.fields[fname].value
                    : null;
            if (this.email) {
                this.loadCard();
            }
        } else if (error) {
            this.loadError = error.body
                ? error.body.message
                : 'Unable to read record.';
        }
    }

    get fieldsToFetch() {
        const base =
            this.objectApiName === 'Lead'
                ? [LEAD_EMAIL, LEAD_NAME]
                : [CONTACT_EMAIL, CONTACT_NAME];
        const ref = this.shareLinkFieldRef;
        return ref ? [...base, ref] : base;
    }

    async loadCard() {
        this.isLoading = true;
        this.loadError = null;
        try {
            this.card = await getCardData({ email: this.email });
        } catch (e) {
            this.loadError =
                (e && e.body && e.body.message) ||
                'Failed to load Extole data.';
        } finally {
            this.isLoading = false;
        }
    }

    // ── Computed view state ─────────────────────────────────────────────────

    get shouldRender() {
        return this.card && this.card.hasAnyData;
    }

    get shouldShowEmpty() {
        return this.card !== null && !this.card.hasAnyData && !this.loadError;
    }

    get hasShareLinks() {
        return (
            this.card && this.card.shareLinks && this.card.shareLinks.length > 0
        );
    }

    get hasFriends() {
        return this.card && this.card.friends && this.card.friends.length > 0;
    }

    get hasReferredBy() {
        return this.card && this.card.referredBy != null;
    }

    get displayName() {
        if (this.sfdcName) return this.sfdcName;
        if (!this.card) return '';
        const first = this.card.firstName || '';
        const last = this.card.lastName || '';
        return (first + ' ' + last).trim() || this.card.email || '';
    }

    get initials() {
        return computeInitials(this.displayName);
    }

    get roleLabel() {
        const advocate = this.hasFriends;
        const friend = this.hasReferredBy;
        if (advocate && friend) return 'Advocate · Referred friend';
        if (advocate) return 'Advocate';
        if (friend) return 'Referred friend';
        return '';
    }

    get decoratedShareLinks() {
        if (!this.hasShareLinks) return [];
        const saved = (this.sfdcShareLink || '').trim();
        return this.card.shareLinks.map((sl) => {
            const c = programColors(sl.program);
            const isSavedOnRecord = !!(
                saved &&
                sl.link &&
                sl.link.trim() === saved
            );
            return {
                ...sl,
                programStyle: `background:${c.fill};color:${c.primary};`,
                isSavedOnRecord
            };
        });
    }

    get programGroups() {
        if (!this.hasFriends) return [];
        const byProgram = new Map();
        for (const f of this.card.friends) {
            const program = f.program || 'unknown';
            if (!byProgram.has(program)) byProgram.set(program, []);
            const earned =
                f.reward &&
                (f.reward.state === 'PAID' ||
                    f.reward.state === 'EARNED' ||
                    f.reward.state === 'SENT');
            const rewardDateStr = earned
                ? formatShortDate(f.reward.dateEarned)
                : null;
            const statusText = earned
                ? rewardDateStr
                    ? `Reward earned ${rewardDateStr}`
                    : 'Reward earned'
                : '';
            const rewardStateText = earned
                ? f.reward.amountLabel
                : 'no reward yet';
            const rewardStateClass = earned
                ? 'reward-amount-earned'
                : 'reward-pending';
            const sfdcUrl = f.sfdcRecordId
                ? `/lightning/r/${f.sfdcObjectType}/${f.sfdcRecordId}/view`
                : null;
            const displayName = f.displayName || f.email || 'Anonymous';
            const milestones = (f.steps || []).map((s) => ({
                key: s.name,
                label: s.label,
                date: s.dateCompleted ? formatShortDate(s.dateCompleted) : null,
                rowClass: s.dateCompleted
                    ? 'milestone-row milestone-row-completed'
                    : 'milestone-row milestone-row-pending'
            }));
            byProgram.get(program).push({
                key: f.personId,
                displayName,
                sfdcUrl,
                isLinked: !!f.sfdcRecordId,
                avatarInitials: computeInitials(displayName),
                avatarClass: earned
                    ? 'avatar avatar-success'
                    : 'avatar avatar-neutral',
                avatarIsEarned: earned,
                statusText,
                rewardStateText,
                rewardStateClass,
                milestones,
                hasMilestones: milestones.length > 0
            });
        }
        const groups = [];
        for (const [program, friends] of byProgram.entries()) {
            const c = programColors(program);
            groups.push({
                program,
                programStyle: `background:${c.fill};color:${c.primary};`,
                friends
            });
        }
        return groups;
    }

    get referredByDecorated() {
        if (!this.hasReferredBy) return null;
        const r = this.card.referredBy;
        const c = programColors(r.program);
        const displayName = r.displayName || r.email || 'Anonymous';
        return {
            ...r,
            displayName,
            sfdcUrl: r.sfdcRecordId
                ? `/lightning/r/${r.sfdcObjectType}/${r.sfdcRecordId}/view`
                : null,
            isLinked: !!r.sfdcRecordId,
            programStyle: `background:${c.fill};color:${c.primary};`,
            avatarInitials: computeInitials(displayName)
        };
    }

    handleCopyLink(event) {
        event.stopPropagation();
        const link = event.currentTarget.dataset.link;
        if (!link) return;
        if (navigator && navigator.clipboard) {
            navigator.clipboard.writeText(link);
        }
    }

    toggleSection(event) {
        const key = event.currentTarget.dataset.section;
        if (!key) return;
        this.sectionCollapsed = {
            ...this.sectionCollapsed,
            [key]: !this.sectionCollapsed[key]
        };
    }

    get shareLinksExpanded() {
        return !this.sectionCollapsed.shareLinks;
    }
    get friendsExpanded() {
        return !this.sectionCollapsed.friends;
    }
    get referredByExpanded() {
        return !this.sectionCollapsed.referredBy;
    }

    get shareLinksChevron() {
        return this.shareLinksExpanded
            ? 'utility:chevrondown'
            : 'utility:chevronright';
    }
    get friendsChevron() {
        return this.friendsExpanded
            ? 'utility:chevrondown'
            : 'utility:chevronright';
    }
    get referredByChevron() {
        return this.referredByExpanded
            ? 'utility:chevrondown'
            : 'utility:chevronright';
    }

    get shareLinksLabel() {
        const n =
            this.card && this.card.shareLinks ? this.card.shareLinks.length : 0;
        return this.shareLinksExpanded ? 'Share Links' : `Share Links (${n})`;
    }

    get friendsLabel() {
        const n = this.card && this.card.friends ? this.card.friends.length : 0;
        return this.friendsExpanded ? 'Friends' : `Friends (${n})`;
    }
}
