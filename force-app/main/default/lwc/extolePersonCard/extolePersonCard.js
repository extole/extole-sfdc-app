import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getCardData from '@salesforce/apex/ExtolePersonCardController.getCardData';
import getFriendDetails from '@salesforce/apex/ExtolePersonCardController.getFriendDetails';
import getShareLinkFieldSetting from '@salesforce/apex/ExtoleBackfillController.getShareLinkFieldSetting';
import ExtolePersonCardModal from 'c/extolePersonCardModal';
import ExtoleReferrersModal from 'c/extoleReferrersModal';
import {
    programColors,
    decorateFriend,
    decorateMilestones,
    describeReward,
    programPillStyle,
    groupByProgram,
    FRIENDS_HELP_TEXT,
    REFERRED_BY_HELP_TEXT,
    formatShortDate
} from 'c/extolePersonCardUtils';

import LEAD_EMAIL from '@salesforce/schema/Lead.Email';
import LEAD_NAME from '@salesforce/schema/Lead.Name';
import CONTACT_EMAIL from '@salesforce/schema/Contact.Email';
import CONTACT_NAME from '@salesforce/schema/Contact.Name';

const FRIEND_BATCH = 5;

export default class ExtolePersonCard extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api disabled = false;

    @track card = null;
    @track friendsLoaded = [];
    @track isLoadingMore = false;
    @track loadMoreError = null;
    @track isLoading = false;
    @track loadError = null;
    // How many referrers show before Show more.
    referrerLimit = FRIEND_BATCH;
    @track sectionCollapsed = {
        shareLinks: true,
        friends: false,
        referredBy: false
    };

    helpText = FRIENDS_HELP_TEXT;
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
            this.friendsLoaded = this.card.friends || [];
            this.loadMoreError = null;
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

    get hasShareLinks() {
        return (
            this.card && this.card.shareLinks && this.card.shareLinks.length > 0
        );
    }

    // Everything this person is in themselves, one block per program. A
    // program that referred them is shown under Referred by, with who referred
    // them; any other is an offer they're in, shown under Rewards.
    get ownBlocks() {
        if (!this.card) return [];
        const referrers = this.card.referrers || [];
        const referrersByProgram = new Map();
        for (const r of referrers) {
            const key = r.program || '';
            if (!referrersByProgram.has(key)) referrersByProgram.set(key, []);
            referrersByProgram.get(key).push(r);
        }
        const blocks = (this.card.ownPrograms || []).map((op, i) => {
            const key = op.program || '';
            const milestones = decorateMilestones(op.steps);
            return {
                key: `${key || 'none'}-${i}`,
                program: op.program,
                programStyle: op.program ? programPillStyle(op.program) : '',
                referrers: this.decorateReferrers(referrersByProgram.get(key)),
                milestones,
                hasMilestones: milestones.length > 0,
                reward: this.rewardFor(op, this.card.ownAmounts),
                rewardReferrerId: op.rewardReferrerId
            };
        });
        for (const b of blocks) b.lines = this.referrerLines(b);
        // A referral with no program entry still gets its row.
        const shown = new Set(blocks.map((b) => b.program || ''));
        for (const [key, rs] of referrersByProgram) {
            if (shown.has(key)) continue;
            blocks.push({
                key: `${key || 'none'}-referral`,
                program: key || null,
                programStyle: key ? programPillStyle(key) : '',
                referrers: this.decorateReferrers(rs),
                milestones: [],
                hasMilestones: false,
                reward: null
            });
            blocks[blocks.length - 1].lines = this.referrerLines(
                blocks[blocks.length - 1]
            );
        }
        return blocks;
    }

    // The reward pill, or nothing when there is no amount, reward or decline.
    rewardFor(op, amounts) {
        const r = describeReward(
            { reward: op.reward, status: op.status },
            amounts && amounts[op.program]
        );
        return r.text ? r : null;
    }

    // One sentence per referrer: "Quality Test in [program]". The first line
    // carries this person's own reward on the right, above their steps, like a
    // friend's row under an advocate.
    referrerLines(block) {
        // The reward goes on the referrer Extole says it came from, else the
        // first one.
        const owner = block.referrers.findIndex(
            (r) =>
                block.rewardReferrerId && r.personId === block.rewardReferrerId
        );
        const rewardIndex = owner < 0 ? 0 : owner;
        return block.referrers.map((r, i) => ({
            key: r.key,
            displayName: r.displayName,
            title: r.email || r.identityValue || r.displayName,
            isLinked: r.isLinked,
            sfdcUrl: r.sfdcUrl,
            dateText: block.referrers.length > 1 ? r.dateText : '',
            program: block.program,
            programStyle: block.programStyle,
            reward: i === rewardIndex ? block.reward : null,
            isOwner: i === rewardIndex
        }));
    }

    // Newest referral first, so the current referrer reads first.
    decorateReferrers(list) {
        return (list || [])
            .slice()
            .sort((a, b) =>
                String(b.referredDate || '').localeCompare(
                    String(a.referredDate || '')
                )
            )
            .map((r, i) => ({
                ...r,
                key: `${r.personId}-${i}`,
                displayName: r.displayName || r.email || 'Anonymous',
                dateText: formatShortDate(r.referredDate),
                sfdcUrl: r.sfdcRecordId
                    ? `/lightning/r/${r.sfdcObjectType}/${r.sfdcRecordId}/view`
                    : null,
                isLinked: !!r.sfdcRecordId
            }));
    }

    get referralBlocks() {
        return this.ownBlocks.filter((b) => b.referrers.length > 0);
    }

    get totalReferrers() {
        return this.referralBlocks.reduce((n, b) => n + b.lines.length, 0);
    }

    // The first referrerLimit referrers across all programs.
    get visibleReferralBlocks() {
        let left = this.referrerLimit;
        return this.referralBlocks
            .map((b) => {
                const take = Math.max(0, Math.min(left, b.lines.length));
                left -= take;
                return {
                    ...b,
                    multi: b.lines.length > 1,
                    lines: b.lines.slice(0, take)
                };
            })
            .filter((b) => b.lines.length > 0);
    }

    // Referrers grouped under their program, one card each. The program's
    // steps sit on the card of the referrer the reward came from, since Extole
    // doesn't split them further.
    get visibleReferralGroups() {
        return this.toReferralGroups(this.visibleReferralBlocks);
    }

    toReferralGroups(blocks) {
        return blocks.map((block) => ({
            key: block.key,
            program: block.program,
            programStyle: block.programStyle,
            cards: block.lines.map((line) => ({
                key: `${block.key}-${line.key}`,
                line,
                search: `${line.displayName} ${line.title || ''}`.toLowerCase(),
                milestones: line.isOwner ? block.milestones : [],
                hasMilestones: line.isOwner && block.hasMilestones
            }))
        }));
    }

    // What a declined friend's reward was: the advocate's own amount, else the
    // program's one reward.
    get declinedAmounts() {
        return {
            ...(this.card.onlyAmounts || {}),
            ...(this.card.advocateAmounts || {})
        };
    }

    get referrersExpandable() {
        return this.totalReferrers > FRIEND_BATCH;
    }

    get referrersShowMoreVisible() {
        return this.totalReferrers > this.referrerLimit;
    }

    get referrersCountText() {
        return `Showing ${Math.min(this.referrerLimit, this.totalReferrers)} of ${this.totalReferrers}`;
    }

    handleShowMoreReferrers() {
        this.referrerLimit += FRIEND_BATCH;
    }

    async handleExpandReferrers(event) {
        event.stopPropagation();
        await ExtoleReferrersModal.open({
            size: 'large',
            groups: this.toReferralGroups(this.referralBlocks)
        });
    }

    get hasReferralBlocks() {
        return this.referralBlocks.length > 0;
    }

    get referredByHelpText() {
        return REFERRED_BY_HELP_TEXT;
    }

    get profileUrl() {
        return this.card && this.card.profileUrl ? this.card.profileUrl : null;
    }

    get hasFriends() {
        return this.totalFriends > 0;
    }

    get totalFriends() {
        return this.card ? this.card.totalFriends || 0 : 0;
    }

    get remainingFriends() {
        return Math.max(0, this.totalFriends - this.friendsLoaded.length);
    }

    get showMoreVisible() {
        return this.remainingFriends > 0;
    }

    get showCountRow() {
        return this.totalFriends > FRIEND_BATCH;
    }

    get friendsCountText() {
        return this.showMoreVisible
            ? `Showing ${this.friendsLoaded.length} of ${this.totalFriends}`
            : `Showing all ${this.totalFriends}`;
    }

    stopClick(event) {
        event.stopPropagation();
    }

    get showMoreLabel() {
        return this.isLoadingMore ? 'Loading…' : 'Show more';
    }

    get displayName() {
        if (this.sfdcName) return this.sfdcName;
        if (!this.card) return '';
        const first = this.card.firstName || '';
        const last = this.card.lastName || '';
        return (first + ' ' + last).trim() || this.card.email || '';
    }

    // The hover text names whose profile the link opens.
    get viewLinkTitle() {
        return this.displayName
            ? `Open ${this.displayName} in My Extole`
            : 'Open this person in My Extole';
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
        return groupByProgram(
            this.friendsLoaded.map((f) =>
                decorateFriend(
                    f,
                    this.card.advocateAmounts,
                    this.declinedAmounts
                )
            )
        );
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

    get referredByChevron() {
        return this.referredByExpanded
            ? 'utility:chevrondown'
            : 'utility:chevronright';
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
            : `Friends (${this.totalFriends})`;
    }

    // An advocate reads: share links, friends, referred by. Anyone else reads:
    // referred by, share links.
    get sectionOrder() {
        return this.hasFriends
            ? { shareLinks: 1, friends: 2, referredBy: 3 }
            : { referredBy: 1, shareLinks: 2, friends: 3 };
    }

    get referredByOrder() {
        return `order:${this.sectionOrder.referredBy}`;
    }

    get shareLinksOrder() {
        return `order:${this.sectionOrder.shareLinks}`;
    }

    get friendsOrder() {
        return `order:${this.sectionOrder.friends}`;
    }

    async handleShowMore() {
        if (this.isLoadingMore || !this.showMoreVisible) return;
        this.isLoadingMore = true;
        this.loadMoreError = null;
        try {
            const loadedIds = new Set(
                this.friendsLoaded.map((f) => f.personId)
            );
            const batch = (this.card.friendRefs || [])
                .filter((r) => !loadedIds.has(r.personId))
                .slice(0, FRIEND_BATCH);
            const refById = new Map(
                (this.card.friendRefs || []).map((r) => [r.personId, r])
            );
            const result = await getFriendDetails({
                personIds: batch.map((r) => r.personId),
                programs: batch.map((r) => r.program),
                identityKeys: batch.map((r) => r.identityKey),
                identityValues: batch.map((r) => r.identityValue)
            });
            const added = (result || []).map((f) => {
                const ref = refById.get(f.personId) || {};
                return {
                    ...f,
                    reward: ref.reward || null,
                    status: ref.status || null
                };
            });
            this.friendsLoaded = [...this.friendsLoaded, ...added];
        } catch (e) {
            this.loadMoreError =
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
            label: this.displayName,
            description: `Friends referred by ${this.displayName}`,
            advocateName: this.displayName,
            totalFriends: this.totalFriends,
            friends: this.friendsLoaded,
            friendRefs: this.card.friendRefs || [],
            advocateAmounts: this.card.advocateAmounts,
            declinedAmounts: this.declinedAmounts,
            profileUrl: this.profileUrl
        });
    }
}
