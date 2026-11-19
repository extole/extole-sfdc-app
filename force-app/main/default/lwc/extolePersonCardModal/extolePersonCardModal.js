import LightningModal from 'lightning/modal';
import { api } from 'lwc';
import getFriendDetails from '@salesforce/apex/ExtolePersonCardController.getFriendDetails';
import {
    decorateFriend,
    groupByProgram,
    FRIENDS_HELP_TEXT
} from 'c/extolePersonCardUtils';

const PAGE_SIZE = 10;
const LOAD_BATCH = 20;

export default class ExtolePersonCardModal extends LightningModal {
    @api advocateName;
    @api totalFriends = 0;
    @api friends = [];
    @api friendRefs = [];
    @api advocateAmounts;
    @api declinedAmounts;
    @api profileUrl;

    helpText = FRIENDS_HELP_TEXT;
    loadedRaw = [];
    refById = new Map();
    loadedIds = new Set();
    closed = false;
    loadError = null;
    loadingRest = false;

    query = '';
    // One filter at a time: 'all', 'rewarded', 'pending' or 'declined'.
    filter = 'all';
    page = 1;

    connectedCallback() {
        for (const ref of this.friendRefs || []) {
            this.refById.set(ref.personId, ref);
        }
        this.loadedRaw = [...(this.friends || [])];
        for (const f of this.loadedRaw) this.loadedIds.add(f.personId);
        this.loadRest();
    }

    disconnectedCallback() {
        this.closed = true;
    }

    // Loads every remaining friend's name and email in the background, one
    // batch per request, so search covers everyone.
    async loadRest() {
        let pending = (this.friendRefs || []).filter(
            (r) => !this.loadedIds.has(r.personId)
        );
        if (!pending.length) return;
        this.loadingRest = true;
        try {
            while (pending.length && !this.closed) {
                const batch = pending.slice(0, LOAD_BATCH);
                // Batches run one after another on purpose: each request needs
                // its own callout budget and the next batch depends on this one.
                // eslint-disable-next-line no-await-in-loop
                const result = await getFriendDetails({
                    personIds: batch.map((r) => r.personId),
                    programs: batch.map((r) => r.program),
                    identityKeys: batch.map((r) => r.identityKey),
                    identityValues: batch.map((r) => r.identityValue)
                });
                if (!result || !result.length) break;
                const added = [];
                for (const f of result) {
                    const ref = this.refById.get(f.personId) || {};
                    added.push({
                        ...f,
                        reward: ref.reward || null,
                        status: ref.status || null
                    });
                    this.loadedIds.add(f.personId);
                }
                this.loadedRaw = [...this.loadedRaw, ...added];
                pending = pending.filter(
                    (r) => !this.loadedIds.has(r.personId)
                );
            }
        } catch (e) {
            this.loadError =
                (e && e.body && e.body.message) ||
                'Some friends could not be loaded.';
        } finally {
            this.loadingRest = false;
        }
    }

    // ── Data ────────────────────────────────────────────────────────────────

    get decorated() {
        return this.loadedRaw.map((f) =>
            decorateFriend(f, this.advocateAmounts, this.declinedAmounts)
        );
    }

    get filtered() {
        const q = this.query.trim().toLowerCase();
        return this.decorated.filter((f) => {
            if (this.filter !== 'all' && f.status !== this.filter) return false;
            return !q || f.searchText.includes(q);
        });
    }

    get pageCount() {
        return Math.max(1, Math.ceil(this.filtered.length / PAGE_SIZE));
    }

    get currentPage() {
        return Math.min(this.page, this.pageCount);
    }

    get pageRows() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filtered.slice(start, start + PAGE_SIZE);
    }

    get groups() {
        return groupByProgram(this.pageRows);
    }

    // ── Header / status text ────────────────────────────────────────────────

    get friendCountLabel() {
        const n = this.totalFriends;
        return `${n} ${n === 1 ? 'friend' : 'friends'}`;
    }

    get showLoading() {
        return this.loadingRest;
    }

    get loadingText() {
        return `Loading names and emails… ${this.loadedRaw.length} of ${this.totalFriends}`;
    }

    get loadingBarStyle() {
        const pct = this.totalFriends
            ? Math.round((this.loadedRaw.length / this.totalFriends) * 100)
            : 0;
        return `width:${pct}%;`;
    }

    get hasResults() {
        return this.filtered.length > 0;
    }

    get emptyText() {
        const stillLoading = this.loadingRest && this.query.trim();
        if (stillLoading) {
            const left = this.totalFriends - this.loadedRaw.length;
            return `No match yet. Still loading ${left} more ${left === 1 ? 'friend' : 'friends'}.`;
        }
        return 'No friends match your search or filter.';
    }

    get rangeText() {
        const total = this.filtered.length;
        if (!total) return '0 results';
        const start = (this.currentPage - 1) * PAGE_SIZE + 1;
        const end = start + this.pageRows.length - 1;
        const stillLoading =
            this.loadingRest && !this.query.trim() && this.filter === 'all';
        return `${start}–${end} of ${total}${stillLoading ? ' loaded' : ''}`;
    }

    // ── Filter buttons ──────────────────────────────────────────────────────

    get filterButtons() {
        return [
            { key: 'all', label: 'All' },
            { key: 'rewarded', label: 'Rewarded' },
            { key: 'pending', label: 'Not rewarded yet' },
            { key: 'declined', label: 'Declined' }
        ].map((b) => {
            const on = this.filter === b.key;
            return {
                ...b,
                cls: on ? 'chip chip-on' : 'chip',
                pressed: String(on)
            };
        });
    }

    // Clicking a button switches straight to it. Clicking the one that is
    // already on turns it off, which goes back to All.
    handleFilter(event) {
        const key = event.currentTarget.dataset.filter;
        this.setFilter(key !== 'all' && this.filter === key ? 'all' : key);
    }

    setFilter(value) {
        this.filter = value;
        this.resetPage();
    }

    // A new search starts from everyone, so a filter left on from earlier
    // can't hide results.
    handleSearch(event) {
        this.query = event.target.value || '';
        this.filter = 'all';
        this.resetPage();
    }

    resetPage() {
        this.page = 1;
        this.scrollListToTop();
    }

    // ── Pagination ──────────────────────────────────────────────────────────

    get showPager() {
        return this.filtered.length > PAGE_SIZE;
    }

    get prevDisabled() {
        return this.currentPage <= 1;
    }

    get nextDisabled() {
        return this.currentPage >= this.pageCount;
    }

    get pageItems() {
        const count = this.pageCount;
        const cur = this.currentPage;
        const nums = new Set([1, count, cur - 1, cur, cur + 1]);
        const sorted = [...nums]
            .filter((n) => n >= 1 && n <= count)
            .sort((a, b) => a - b);
        const items = [];
        let prev = 0;
        for (const n of sorted) {
            if (n - prev > 1) {
                items.push({ key: `gap-${n}`, isGap: true });
            }
            items.push({
                key: `p-${n}`,
                isGap: false,
                number: n,
                cls: n === cur ? 'page-btn page-btn-on' : 'page-btn',
                current: n === cur ? 'page' : null
            });
            prev = n;
        }
        return items;
    }

    handlePage(event) {
        this.page = Number(event.currentTarget.dataset.page);
        this.scrollListToTop();
    }

    handlePrev() {
        if (this.currentPage > 1) {
            this.page = this.currentPage - 1;
            this.scrollListToTop();
        }
    }

    handleNext() {
        if (this.currentPage < this.pageCount) {
            this.page = this.currentPage + 1;
            this.scrollListToTop();
        }
    }

    scrollListToTop() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const el = this.template.querySelector('.list');
            if (el && el.scrollIntoView) el.scrollIntoView({ block: 'start' });
        });
    }
}
