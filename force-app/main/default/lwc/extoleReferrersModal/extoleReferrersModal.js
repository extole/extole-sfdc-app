import LightningModal from 'lightning/modal';
import { api } from 'lwc';

// Everyone who referred this person, with their steps and reward, and search.
export default class ExtoleReferrersModal extends LightningModal {
    @api groups = [];

    query = '';

    handleSearch(event) {
        this.query = event.target.value || '';
    }

    get visibleGroups() {
        const q = this.query.trim().toLowerCase();
        return (this.groups || [])
            .map((g) => ({
                ...g,
                cards: g.cards.filter((c) => !q || c.search.includes(q))
            }))
            .filter((g) => g.cards.length > 0);
    }

    get hasResults() {
        return this.visibleGroups.length > 0;
    }
}
