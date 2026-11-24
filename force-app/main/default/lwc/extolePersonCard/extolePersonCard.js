import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getCardData from '@salesforce/apex/ExtolePersonCardController.getCardData';
import getFriendDetails from '@salesforce/apex/ExtolePersonCardController.getFriendDetails';
import getReferrerDetails from '@salesforce/apex/ExtolePersonCardController.getReferrerDetails';
import getShareLinkFieldSetting from '@salesforce/apex/ExtoleBackfillController.getShareLinkFieldSetting';
import ExtolePersonCardModal from 'c/extolePersonCardModal';
import {
    programColors,
    computeInitials,
    groupByProgram,
    groupReferrers,
    referrerKey,
    mergeReferrers,
    detailsArgs,
    attachRewards
} from 'c/extolePersonCardUtils';

import LEAD_EMAIL from '@salesforce/schema/Lead.Email';
import LEAD_NAME from '@salesforce/schema/Lead.Name';
import CONTACT_EMAIL from '@salesforce/schema/Contact.Email';
import CONTACT_NAME from '@salesforce/schema/Contact.Name';

export default class ExtolePersonCard extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api disabled = false;

    @track card = null;
    @track isLoading = false;
    @track isLoadingMore = false;
    @track friendsLoaded = [];
    @track referrersLoaded = [];
    @track isLoadingMoreReferrers = false;
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

    get isAccount() {
        return this.objectApiName === 'Account';
    }

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

    // Account fields are referenced by string: PersonEmail and IsPersonAccount
    // only exist when Person Accounts is enabled, so they can't be schema imports.
    @wire(getRecord, {
        recordId: '$recordId',
        fields: '$requiredFields',
        optionalFields: '$optionalFields'
    })
    wiredRecord({ data, error }) {
        if (data) {
            const shareFieldName = this.configuredShareLinkField;
            this.sfdcShareLink =
                shareFieldName && data.fields && data.fields[shareFieldName]
                    ? data.fields[shareFieldName].value
                    : null;
            if (this.isAccount) {
                const isPerson =
                    data.fields.IsPersonAccount &&
                    data.fields.IsPersonAccount.value;
                if (!isPerson) {
                    return;
                }
                this.email = data.fields.PersonEmail
                    ? data.fields.PersonEmail.value
                    : null;
                this.sfdcName = data.fields.Name
                    ? data.fields.Name.value
                    : null;
            } else {
                this.email = getFieldValue(data, this.emailField);
                this.sfdcName = getFieldValue(data, this.nameField);
            }
            if (this.email) {
                this.loadCard();
            }
        } else if (error) {
            this.loadError = error.body
                ? error.body.message
                : 'Unable to read record.';
        }
    }

    get requiredFields() {
        if (this.isAccount) return ['Account.Name'];
        return this.objectApiName === 'Lead'
            ? [LEAD_EMAIL, LEAD_NAME]
            : [CONTACT_EMAIL, CONTACT_NAME];
    }

    get optionalFields() {
        const ref = this.shareLinkFieldRef;
        const extra = this.isAccount
            ? ['Account.PersonEmail', 'Account.IsPersonAccount']
            : [];
        return ref ? [...extra, ref] : extra;
    }

    async loadCard() {
        this.isLoading = true;
        this.loadError = null;
        try {
            this.card = await getCardData({ email: this.email });
            this.friendsLoaded = (this.card && this.card.friends) || [];
            this.referrersLoaded = (this.card && this.card.referrers) || [];
        } catch (e) {
            this.loadError =
                (e && e.body && e.body.message) ||
                'Failed to load Extole data.';
        } finally {
            this.isLoading = false;
        }
    }

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
        return this.totalFriends > 0;
    }

    get totalFriends() {
        return this.card ? this.card.totalFriends || 0 : 0;
    }

    get friendBatch() {
        return this.card && this.card.friends ? this.card.friends.length : 0;
    }

    get friendsTruncated() {
        return !!(this.card && this.card.friendsTruncated);
    }

    get totalFriendsText() {
        return this.friendsTruncated
            ? `${this.totalFriends}+`
            : `${this.totalFriends}`;
    }

    get friendsExpandable() {
        return this.totalFriends > this.friendBatch;
    }

    get friendsShowMoreVisible() {
        return this.totalFriends > this.friendsLoaded.length;
    }

    get friendsCountText() {
        return `Showing ${this.friendsLoaded.length} of ${this.totalFriendsText}`;
    }

    get totalReferrers() {
        return this.card ? this.card.totalReferrers || 0 : 0;
    }

    get hasReferredBy() {
        return this.totalReferrers > 0;
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
        return groupByProgram(this.friendsLoaded, this.card.advocateAmounts);
    }

    async handleShowMore() {
        if (this.isLoadingMore) return;
        const have = new Set(this.friendsLoaded.map((f) => f.personId));
        const next = (this.card.friendRefs || [])
            .filter((r) => !have.has(r.personId))
            .slice(0, this.friendBatch);
        if (next.length === 0) return;
        this.isLoadingMore = true;
        this.loadError = null;
        try {
            const more = await getFriendDetails(detailsArgs(next));
            if (!more || more.length === 0) {
                this.loadError = 'Could not load more friends. Try again.';
            } else {
                this.friendsLoaded = [
                    ...this.friendsLoaded,
                    ...attachRewards(more, next)
                ];
            }
        } catch (e) {
            this.loadError =
                (e && e.body && e.body.message) ||
                'Could not load more friends.';
        } finally {
            this.isLoadingMore = false;
        }
    }

    async handleExpand(event) {
        event.stopPropagation();
        await ExtolePersonCardModal.open({
            size: 'large',
            friendRefs: this.card.friendRefs || [],
            loaded: this.friendsLoaded,
            friendsTruncated: this.friendsTruncated,
            advocateAmounts: this.card.advocateAmounts
        });
    }

    get referrerGroups() {
        return groupReferrers(this.referrersLoaded);
    }

    get referrerBatch() {
        return this.card && this.card.referrers
            ? this.card.referrers.length
            : 0;
    }

    get referrersExpandable() {
        return this.totalReferrers > this.referrerBatch;
    }

    get referrersShowMoreVisible() {
        return this.totalReferrers > this.referrersLoaded.length;
    }

    get referrersCountText() {
        return `Showing ${this.referrersLoaded.length} of ${this.totalReferrers}`;
    }

    async handleShowMoreReferrers() {
        if (this.isLoadingMoreReferrers) return;
        const have = new Set(this.referrersLoaded.map(referrerKey));
        const next = (this.card.referrerRefs || [])
            .filter((r) => !have.has(referrerKey(r)))
            .slice(0, this.referrerBatch);
        if (next.length === 0) return;
        this.isLoadingMoreReferrers = true;
        this.loadError = null;
        try {
            const more = await getReferrerDetails({
                personIds: next.map((r) => r.personId)
            });
            if (!more || more.length === 0) {
                this.loadError = 'Could not load more referrers. Try again.';
            } else {
                this.referrersLoaded = [
                    ...this.referrersLoaded,
                    ...mergeReferrers(more, next)
                ];
            }
        } catch (e) {
            this.loadError =
                (e && e.body && e.body.message) ||
                'Could not load more referrers.';
        } finally {
            this.isLoadingMoreReferrers = false;
        }
    }

    handleCopyLink(event) {
        event.stopPropagation();
        const link = event.currentTarget.dataset.link;
        if (!link) return;
        // navigator.clipboard.writeText commonly rejects inside Salesforce
        // Lightning's sandboxed iframe -- fall back to a hidden-textarea +
        // execCommand('copy') when the Clipboard API is unavailable or rejects.
        if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard
                .writeText(link)
                .catch(() => this.copyLinkFallback(link));
        } else {
            this.copyLinkFallback(link);
        }
    }

    copyLinkFallback(link) {
        const textarea = document.createElement('textarea');
        textarea.value = link;
        textarea.style.position = 'fixed';
        textarea.style.opacity = '0';
        document.body.appendChild(textarea);
        textarea.focus();
        textarea.select();
        try {
            document.execCommand('copy');
        } catch {
            // Nothing further to fall back to -- consistent with this
            // handler's existing no-feedback behavior on failure.
        }
        document.body.removeChild(textarea);
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

    get referredByLabel() {
        return this.referredByExpanded
            ? 'Referred by'
            : `Referred by (${this.totalReferrers})`;
    }

    get friendsLabel() {
        return this.friendsExpanded
            ? 'Friends'
            : `Friends (${this.totalFriendsText})`;
    }
}
