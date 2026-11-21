/* eslint-disable @lwc/lwc/no-async-operation, no-await-in-loop */
import { createElement } from 'lwc';
import ExtolePersonCardModal from 'c/extolePersonCardModal';
import getFriendDetails from '@salesforce/apex/ExtolePersonCardController.getFriendDetails';

jest.mock(
    'lightning/modal',
    () => {
        const { LightningElement } = require('lwc');
        return { __esModule: true, default: class extends LightningElement {} };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/ExtolePersonCardController.getFriendDetails',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function statusOf(i) {
    if (i % 7 === 0) return 'rewarded';
    return i % 11 === 0 ? 'declined' : 'pending';
}
const ref = (i) => ({
    personId: `p${i}`,
    program: 'refer-a-friend',
    status: statusOf(i),
    reward:
        statusOf(i) === 'rewarded'
            ? { state: 'EARNED', amountLabel: '$5' }
            : null
});
const friend = (i) => ({
    personId: `p${i}`,
    program: 'refer-a-friend',
    displayName: `Friend ${i}`
});
const refs = (n) => Array.from({ length: n }, (_, i) => ref(i));

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
async function settle() {
    for (let i = 0; i < 5; i++) await flush();
}

function mount(friendRefs, loaded = [], friendsTruncated = false) {
    const el = createElement('c-extole-person-card-modal', {
        is: ExtolePersonCardModal
    });
    el.friendRefs = friendRefs;
    el.loaded = loaded;
    el.friendsTruncated = friendsTruncated;
    document.body.appendChild(el);
    return el;
}

const names = (el) =>
    [...el.shadowRoot.querySelectorAll('c-extole-friend-card')].map(
        (c) => c.friend.displayName
    );
const buttons = (el) => [...el.shadowRoot.querySelectorAll('lightning-button')];

beforeEach(() => {
    getFriendDetails.mockReset();
    getFriendDetails.mockImplementation(({ personIds }) =>
        Promise.resolve(personIds.map((id) => friend(Number(id.slice(1)))))
    );
});

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
});

describe('extolePersonCardModal', () => {
    it('shows ten to a page and loads only what it shows', async () => {
        const el = mount(refs(95));
        await settle();

        expect(names(el)).toHaveLength(10);
        expect(names(el)[0]).toBe('Friend 0');
        expect(getFriendDetails).toHaveBeenCalledTimes(1);
        expect(getFriendDetails.mock.calls[0][0].personIds).toHaveLength(10);
        expect(getFriendDetails.mock.calls[0][0].programs).toHaveLength(10);
        expect(el.shadowRoot.querySelector('.pager-range').textContent).toBe(
            '1–10 of 95'
        );
    });

    it('shows a plus on the count when the card could not read every friend', async () => {
        const el = mount(refs(1000), [], true);
        await settle();

        expect(el.shadowRoot.querySelector('.pager-range').textContent).toBe(
            '1–10 of 1000+'
        );
    });

    it('does not look up friends the card already loaded', async () => {
        const loaded = Array.from({ length: 10 }, (_, i) => friend(i));
        const el = mount(refs(30), loaded);
        await settle();

        expect(names(el)).toHaveLength(10);
        expect(getFriendDetails).not.toHaveBeenCalled();
    });

    it('moves between pages and reaches the last short page', async () => {
        const el = mount(refs(25));
        await settle();
        const [prev, next] = buttons(el);
        expect(prev.disabled).toBe(true);

        next.click();
        await settle();
        next.click();
        await settle();

        expect(names(el)).toHaveLength(5);
        expect(names(el)[0]).toBe('Friend 20');
        expect(el.shadowRoot.querySelector('.pager-range').textContent).toBe(
            '21–25 of 25'
        );
        expect(buttons(el)[1].disabled).toBe(true);
    });

    it('asks again when a call only returns some of the page', async () => {
        getFriendDetails
            .mockImplementationOnce(({ personIds }) =>
                Promise.resolve(
                    personIds
                        .slice(0, 4)
                        .map((id) => friend(Number(id.slice(1))))
                )
            )
            .mockImplementation(({ personIds }) =>
                Promise.resolve(
                    personIds.map((id) => friend(Number(id.slice(1))))
                )
            );
        const el = mount(refs(10));
        await settle();

        expect(getFriendDetails).toHaveBeenCalledTimes(2);
        expect(getFriendDetails.mock.calls[1][0].personIds).toHaveLength(6);
        expect(names(el)).toHaveLength(10);
    });

    it('says so when nothing comes back, instead of looping', async () => {
        getFriendDetails.mockResolvedValue([]);
        const el = mount(refs(10));
        await settle();

        expect(getFriendDetails).toHaveBeenCalledTimes(1);
        expect(el.shadowRoot.querySelector('.error-banner')).not.toBeNull();
    });

    it('filters by reward status and pages within the filtered friends', async () => {
        const el = mount(refs(100));
        await settle();
        const chips = () => [...el.shadowRoot.querySelectorAll('.chip')];
        const click = async (label) => {
            chips()
                .find((c) => c.textContent.trim() === label)
                .click();
            await settle();
        };

        await click('Rewarded');
        expect(el.shadowRoot.querySelector('.pager-range').textContent).toBe(
            '1–10 of 15'
        );
        expect(names(el)[0]).toBe('Friend 0');
        expect(names(el)[1]).toBe('Friend 7');

        await click('Declined');
        expect(el.shadowRoot.querySelector('.pager-range').textContent).toBe(
            '1–8 of 8'
        );
        expect(names(el)).toHaveLength(8);

        await click('Not rewarded yet');
        expect(el.shadowRoot.querySelector('.pager-range').textContent).toBe(
            '1–10 of 77'
        );

        await click('All');
        expect(el.shadowRoot.querySelector('.pager-range').textContent).toBe(
            '1–10 of 100'
        );
    });

    it('lists a friend with an unknown status under All, not under Not rewarded yet', async () => {
        const unknown = refs(3).map((r) => ({ ...r, status: null }));
        const el = mount(unknown);
        await settle();
        expect(names(el)).toHaveLength(3);

        [...el.shadowRoot.querySelectorAll('.chip')]
            .find((c) => c.textContent.trim() === 'Not rewarded yet')
            .click();
        await settle();

        expect(names(el)).toHaveLength(0);
    });

    it('says so when no friend matches the filter', async () => {
        const el = mount(refs(5).filter((r) => r.status !== 'declined'));
        await settle();
        [...el.shadowRoot.querySelectorAll('.chip')]
            .find((c) => c.textContent.trim() === 'Declined')
            .click();
        await settle();

        expect(el.shadowRoot.querySelector('.empty')).not.toBeNull();
        expect(names(el)).toHaveLength(0);
    });

    it('keeps the status and reward the card already knew', async () => {
        const el = mount(refs(10));
        await settle();

        const first = el.shadowRoot.querySelector(
            'c-extole-friend-card'
        ).friend;
        expect(first.status).toBe('rewarded');
        expect(first.rewardStateText).toBe('$5 earned');
    });
});
