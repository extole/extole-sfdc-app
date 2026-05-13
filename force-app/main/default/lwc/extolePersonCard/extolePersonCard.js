import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getCardSkeleton from '@salesforce/apex/ExtolePersonCardController.getCardSkeleton';
import getFriendDetail from '@salesforce/apex/ExtolePersonCardController.getFriendDetail';
import attachSfdcLinks from '@salesforce/apex/ExtolePersonCardController.attachSfdcLinks';

import LEAD_EMAIL from '@salesforce/schema/Lead.Email';
import LEAD_NAME from '@salesforce/schema/Lead.Name';
import CONTACT_EMAIL from '@salesforce/schema/Contact.Email';
import CONTACT_NAME from '@salesforce/schema/Contact.Name';

const PALETTE = [
    { primary: '#1D9E75', fill: 'rgba(29, 158, 117, 0.12)' },
    { primary: '#2563EB', fill: 'rgba(37, 99, 235, 0.10)'  },
    { primary: '#8B5CF6', fill: 'rgba(139, 92, 246, 0.10)' },
    { primary: '#F97316', fill: 'rgba(249, 115, 22, 0.12)' },
    { primary: '#E94560', fill: 'rgba(233, 69, 96, 0.10)'  }
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

    @track card = null;
    @track isLoading = false;
    @track loadError = null;
    @track sectionCollapsed = { shareLinks: false, friends: true, referredBy: false };
    @track engagementCollapsed = {};

    email = null;
    sfdcName = null;
    friendsDetailRequested = false;

    get emailField() {
        return this.objectApiName === 'Lead' ? LEAD_EMAIL : CONTACT_EMAIL;
    }

    get nameField() {
        return this.objectApiName === 'Lead' ? LEAD_NAME : CONTACT_NAME;
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$fieldsToFetch' })
    wiredRecord({ data, error }) {
        if (data) {
            this.email    = getFieldValue(data, this.emailField);
            this.sfdcName = getFieldValue(data, this.nameField);
            if (this.email) {
                this.loadCard();
            }
        } else if (error) {
            this.loadError = error.body ? error.body.message : 'Unable to read record.';
        }
    }

    get fieldsToFetch() {
        return this.objectApiName === 'Lead'
            ? [LEAD_EMAIL, LEAD_NAME]
            : [CONTACT_EMAIL, CONTACT_NAME];
    }

    /**
     * Eager phase — runs on initial render:
     *  - Fetch skeleton (advocate identity, share links, rewards, friend stubs).
     *  - If there's a referred-by email, cross-link it to SFDC (one cheap SOQL).
     *
     * Friend-detail fan-out (the expensive parallel batch) is deferred to
     * loadFriendDetails(), which fires only when the user expands the Friends
     * section. Many users only need share links — no point burning ~10 callouts
     * for relationship detail they'll never look at.
     */
    async loadCard() {
        this.isLoading = true;
        this.loadError = null;
        try {
            const skeleton = await getCardSkeleton({ email: this.email });
            this.card = skeleton;
            this.isLoading = false;

            if (skeleton && skeleton.referredBy && skeleton.referredBy.email) {
                try {
                    const links = await attachSfdcLinks({ emails: [skeleton.referredBy.email] });
                    this.applySfdcLinks(links);
                } catch (e) {
                    // Best-effort.
                }
            }
        } catch (e) {
            this.loadError = (e && e.body && e.body.message) || 'Failed to load Extole data.';
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Lazy phase — runs the first time the user expands the Friends section.
     * Parallel per-friend detail fetch + bulk SFDC cross-link for friend emails.
     */
    async loadFriendDetails() {
        if (this.friendsDetailRequested) return;
        if (!this.card || !this.card.friendRequests || this.card.friendRequests.length === 0) return;
        this.friendsDetailRequested = true;

        try {
            const friendPromises = this.card.friendRequests.map((req, idx) =>
                getFriendDetail({
                    friendPersonId: req.friendPersonId,
                    relsJson:       req.relsJson,
                    milestonesJson: req.milestonesJson,
                    rewardsJson:    req.rewardsJson
                }).then(friend => {
                    this.replaceFriendAt(idx, friend);
                    return friend;
                }).catch(() => null)
            );
            const friends = await Promise.all(friendPromises);

            const emails = [];
            for (const f of friends) {
                if (f && f.email) emails.push(f.email);
            }
            if (emails.length > 0) {
                try {
                    const links = await attachSfdcLinks({ emails });
                    this.applySfdcLinks(links);
                } catch (e) {
                    // Best-effort.
                }
            }
        } catch (e) {
            // Allow retry by clearing the flag.
            this.friendsDetailRequested = false;
        }
    }

    /** Replace one friend stub with its resolved detail. The whole card is
     *  reassigned to trigger reactive recomputation of derived getters. */
    replaceFriendAt(idx, friend) {
        if (!this.card || !this.card.friends || !friend) return;
        const newFriends = this.card.friends.slice();
        newFriends[idx] = friend;
        this.card = { ...this.card, friends: newFriends };
    }

    applySfdcLinks(links) {
        if (!Array.isArray(links) || links.length === 0) return;
        const byEmail = {};
        for (const l of links) {
            if (l && l.email) byEmail[l.email.toLowerCase()] = l;
        }
        const friends = (this.card.friends || []).map(f => {
            if (!f.email) return f;
            const link = byEmail[f.email.toLowerCase()];
            if (!link) return f;
            return { ...f, sfdcRecordId: link.recordId, sfdcObjectType: link.objectType };
        });
        let referredBy = this.card.referredBy;
        if (referredBy && referredBy.email) {
            const link = byEmail[referredBy.email.toLowerCase()];
            if (link) {
                referredBy = { ...referredBy, sfdcRecordId: link.recordId, sfdcObjectType: link.objectType };
            }
        }
        this.card = { ...this.card, friends, referredBy };
    }

    // ── Computed view state ─────────────────────────────────────────────────

    get shouldRender() {
        return this.card && this.card.hasAnyData;
    }

    get hasShareLinks() {
        return this.card && this.card.shareLinks && this.card.shareLinks.length > 0;
    }

    get hasFriends() {
        return this.card && this.card.friends && this.card.friends.length > 0;
    }

    get hasReferredBy() {
        return this.card && this.card.referredBy != null;
    }

    get displayName() {
        return this.sfdcName || (this.card && this.card.displayName) || '';
    }

    get initials() {
        return computeInitials(this.displayName);
    }

    get roleLabel() {
        const advocate = this.hasFriends;
        const friend   = this.hasReferredBy;
        if (advocate && friend)  return 'Advocate · Referred friend';
        if (advocate)            return 'Advocate';
        if (friend)              return 'Referred friend';
        return '';
    }

    get decoratedShareLinks() {
        if (!this.hasShareLinks) return [];
        return this.card.shareLinks.map(sl => {
            const c = programColors(sl.program);
            return {
                ...sl,
                programStyle: `background:${c.fill};color:${c.primary};`
            };
        });
    }

    get programGroups() {
        if (!this.hasFriends) return [];
        const byProgram = new Map();
        for (const f of this.card.friends) {
            const friendInitials = computeInitials(f.displayName || f.email);
            const sfdcUrl = f.sfdcRecordId
                ? `/lightning/r/${f.sfdcObjectType}/${f.sfdcRecordId}/view`
                : null;
            const isLoadingFriend = !f.email && !(f.displayName && f.displayName.length > 0);
            for (const eng of (f.engagements || [])) {
                const program = eng.program || 'unknown';
                if (!byProgram.has(program)) byProgram.set(program, []);
                const earned = eng.reward
                    && (eng.reward.state === 'PAID' || eng.reward.state === 'EARNED');
                const rewardDateStr = earned
                    ? formatShortDate(eng.reward.earnedDate)
                    : null;
                const statusText = earned
                    ? (rewardDateStr ? `Reward earned ${rewardDateStr}` : 'Reward earned')
                    : '';
                const rewardStateText = earned
                    ? eng.reward.amountLabel
                    : 'no reward yet';
                const rewardStateClass = earned ? 'reward-amount-earned' : 'reward-pending';
                const milestones = (eng.milestones || []).map(m => ({
                    ...m,
                    rowClass: m.completed
                        ? 'milestone-row milestone-row-completed'
                        : 'milestone-row milestone-row-pending',
                    dateStr: m.completed ? formatShortDate(m.eventDate) : ''
                }));
                const displayName = f.displayName || f.email || (isLoadingFriend ? 'Loading…' : f.friendPersonId);
                const engagementKey = `${f.friendPersonId}__${eng.campaignId || program}`;
                const hasMilestones = !earned && milestones.length > 0;
                const collapsed = !!this.engagementCollapsed[engagementKey];
                const showMilestones = hasMilestones && !collapsed;
                byProgram.get(program).push({
                    key: engagementKey,
                    friendPersonId: f.friendPersonId,
                    displayName,
                    sfdcUrl,
                    isLinked: !!f.sfdcRecordId,
                    avatarInitials: isLoadingFriend ? '…' : friendInitials,
                    avatarClass: isLoadingFriend
                        ? 'avatar avatar-loading'
                        : (earned ? 'avatar avatar-success' : 'avatar avatar-neutral'),
                    avatarIsEarned: earned,
                    statusText,
                    rewardStateText,
                    rewardStateClass,
                    showMilestones,
                    toggleable: hasMilestones,
                    chevronName: showMilestones ? 'utility:chevrondown' : 'utility:chevronright',
                    headerClass: hasMilestones
                        ? 'engagement-header engagement-header-clickable'
                        : 'engagement-header',
                    milestones
                });
            }
        }
        const groups = [];
        for (const [program, engagements] of byProgram.entries()) {
            const c = programColors(program);
            groups.push({
                program,
                programStyle: `background:${c.fill};color:${c.primary};`,
                engagements
            });
        }
        return groups;
    }

    get referredByDecorated() {
        if (!this.hasReferredBy) return null;
        const r = this.card.referredBy;
        const c = programColors(r.program);
        return {
            ...r,
            sfdcUrl: r.sfdcRecordId ? `/lightning/r/${r.sfdcObjectType}/${r.sfdcRecordId}/view` : null,
            isLinked: !!r.sfdcRecordId,
            programStyle: `background:${c.fill};color:${c.primary};`,
            avatarInitials: computeInitials(r.displayName || r.email)
        };
    }

    handleCopyLink(event) {
        // Don't let the copy click bubble up and toggle the engagement card.
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
        const wasCollapsed = !!this.sectionCollapsed[key];
        this.sectionCollapsed = {
            ...this.sectionCollapsed,
            [key]: !wasCollapsed
        };
        // Kick off the expensive friend-detail fetch the first time the
        // Friends section is opened.
        if (key === 'friends' && wasCollapsed) {
            this.loadFriendDetails();
        }
    }

    toggleEngagement(event) {
        const key = event.currentTarget.dataset.key;
        if (!key) return;
        this.engagementCollapsed = {
            ...this.engagementCollapsed,
            [key]: !this.engagementCollapsed[key]
        };
    }

    get shareLinksExpanded() { return !this.sectionCollapsed.shareLinks; }
    get friendsExpanded()    { return !this.sectionCollapsed.friends; }
    get referredByExpanded() { return !this.sectionCollapsed.referredBy; }

    get shareLinksChevron() { return this.shareLinksExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }
    get friendsChevron()    { return this.friendsExpanded    ? 'utility:chevrondown' : 'utility:chevronright'; }
    get referredByChevron() { return this.referredByExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }

    get shareLinksLabel() {
        const n = this.card && this.card.shareLinks ? this.card.shareLinks.length : 0;
        return this.shareLinksExpanded ? 'Share Links' : `Share Links (${n})`;
    }

    get friendsLabel() {
        const n = this.card && this.card.friends ? this.card.friends.length : 0;
        return this.friendsExpanded ? 'Friends' : `Friends (${n})`;
    }
}
