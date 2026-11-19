/* eslint-disable @lwc/lwc/no-async-operation */
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

const TOTAL = 1000;
const INITIAL = 10;

// Every 7th friend is rewarded, every 11th (that is not rewarded) is declined,
// the rest are pending. Of 1000: 143 rewarded, 78 declined, 779 pending.
function statusOf(i) {
    if (i % 7 === 0) return 'rewarded';
    return i % 11 === 0 ? 'declined' : 'pending';
}

function ref(i) {
    return {
        personId: `p${i}`,
        program: i % 2 ? 'refer-a-friend' : 'member-get-member',
        identityKey: 'email',
        identityValue: `f${i}@example.com`,
        reward: i % 7 === 0 ? { state: 'EARNED', amountLabel: '$50' } : null,
        status: statusOf(i)
    };
}

function friend(i) {
    return {
        personId: `p${i}`,
        program: ref(i).program,
        displayName: `Friend ${i}`,
        email: `f${i}@example.com`,
        steps: [{ name: 's', label: 'Signed Up', dateCompleted: '2026-10-21' }]
    };
}

function idOf(personId) {
    return Number(personId.slice(1));
}

const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

async function until(condition, limit = 3000) {
    for (let i = 0; i < limit; i++) {
        if (condition()) return;
        // eslint-disable-next-line no-await-in-loop
        await tick();
    }
    throw new Error('condition never became true');
}

function mount(total = TOTAL) {
    const refs = Array.from({ length: total }, (_, i) => ref(i));
    const element = createElement('c-extole-person-card-modal', {
        is: ExtolePersonCardModal
    });
    element.advocateName = 'Riley Thompson';
    element.totalFriends = total;
    element.friendRefs = refs;
    element.friends = refs.slice(0, INITIAL).map((r) => ({
        ...friend(idOf(r.personId)),
        reward: r.reward,
        status: r.status
    }));
    document.body.appendChild(element);
    return element;
}

const q = (el, sel) => el.shadowRoot.querySelector(sel);
const qa = (el, sel) => Array.from(el.shadowRoot.querySelectorAll(sel));
const cards = (el) => qa(el, 'c-extole-friend-card');
const range = (el) => q(el, '.range-text').textContent;

async function typeSearch(el, value) {
    const input = q(el, '.search-input');
    input.value = value;
    input.dispatchEvent(new CustomEvent('input'));
    await tick();
}

describe('c-extole-person-card-modal with a large advocate', () => {
    beforeEach(() => {
        getFriendDetails.mockReset();
        // A little latency so tests can observe the loading state and closing mid-load.
        getFriendDetails.mockImplementation(
            ({ personIds }) =>
                new Promise((resolve) =>
                    setTimeout(
                        () => resolve(personIds.map((id) => friend(idOf(id)))),
                        3
                    )
                )
        );
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows the first page straight away and loads the rest in batches', async () => {
        const el = mount();
        await tick();
        expect(cards(el)).toHaveLength(10);
        expect(q(el, '.loading-text')).not.toBeNull();

        await until(() => q(el, '.loading-text') === null);
        expect(range(el)).toBe(`1–10 of ${TOTAL}`);
        const batches = getFriendDetails.mock.calls.length;
        expect(batches).toBe(Math.ceil((TOTAL - INITIAL) / 20));
    });

    it('never asks for the same friend twice', async () => {
        const el = mount();
        await until(() => q(el, '.loading-text') === null);
        const asked = getFriendDetails.mock.calls.flatMap(
            ([args]) => args.personIds
        );
        expect(new Set(asked).size).toBe(asked.length);
        expect(asked).toHaveLength(TOTAL - INITIAL);
    });

    it('passes identity keys and values with each batch', async () => {
        mount(30);
        await until(() => getFriendDetails.mock.calls.length > 0);
        const [args] = getFriendDetails.mock.calls[0];
        expect(args.identityKeys).toHaveLength(args.personIds.length);
        expect(args.identityValues[0]).toBe('f10@example.com');
    });

    it('copes when the server returns fewer friends than requested', async () => {
        getFriendDetails.mockImplementation(({ personIds }) =>
            Promise.resolve(personIds.slice(0, 7).map((id) => friend(idOf(id))))
        );
        const el = mount(200);
        await until(() => q(el, '.loading-text') === null);
        expect(range(el)).toBe('1–10 of 200');
        const asked = getFriendDetails.mock.calls.flatMap(
            ([args]) => args.personIds
        );
        expect(new Set(asked).size).toBe(190);
    });

    it('stops loading and shows an error banner if a batch fails', async () => {
        let calls = 0;
        getFriendDetails.mockImplementation(({ personIds }) => {
            calls += 1;
            if (calls === 3)
                return Promise.reject({ body: { message: 'boom' } });
            return Promise.resolve(personIds.map((id) => friend(idOf(id))));
        });
        const el = mount();
        await until(() => q(el, '.error-banner') !== null);
        expect(q(el, '.error-banner').textContent).toContain('boom');
        await tick();
        expect(getFriendDetails).toHaveBeenCalledTimes(3);
        expect(q(el, '.loading-text')).toBeNull();
    });

    it('stops asking for more once the modal is closed', async () => {
        const el = mount();
        await until(() => getFriendDetails.mock.calls.length >= 2);
        document.body.removeChild(el);
        const callsAtClose = getFriendDetails.mock.calls.length;
        await tick();
        await tick();
        await tick();
        expect(getFriendDetails.mock.calls.length).toBeLessThanOrEqual(
            callsAtClose + 1
        );
        expect(getFriendDetails.mock.calls.length).toBeLessThan(10);
    });

    it('does not loop forever if the server returns nothing', async () => {
        getFriendDetails.mockImplementation(() => Promise.resolve([]));
        const el = mount(100);
        await until(() => q(el, '.loading-text') === null);
        expect(getFriendDetails).toHaveBeenCalledTimes(1);
    });

    it('searches by name and by email across everyone', async () => {
        const el = mount();
        await until(() => q(el, '.loading-text') === null);

        await typeSearch(el, 'f777@');
        expect(cards(el)).toHaveLength(1);
        expect(range(el)).toBe('1–1 of 1');

        await typeSearch(el, 'friend 99');
        // Friend 99, 990–999
        expect(range(el)).toBe('1–10 of 11');

        await typeSearch(el, 'zzz-no-match');
        expect(cards(el)).toHaveLength(0);
        expect(q(el, '.empty')).not.toBeNull();
        expect(range(el)).toBe('0 results');
    });

    it('treats regex characters in the search as plain text', async () => {
        const el = mount(50);
        await until(() => q(el, '.loading-text') === null);
        await typeSearch(el, '.*');
        expect(cards(el)).toHaveLength(0);
        await typeSearch(el, '(');
        expect(cards(el)).toHaveLength(0);
    });

    it('paginates to the last page and clamps the controls', async () => {
        const el = mount();
        await until(() => q(el, '.loading-text') === null);

        const buttons = () => qa(el, '.pager .page-btn');
        const next = () => buttons()[buttons().length - 1];
        const prev = () => buttons()[0];
        expect(prev().disabled).toBe(true);

        for (let i = 0; i < 99; i++) {
            next().click();
            // eslint-disable-next-line no-await-in-loop
            await tick();
        }
        expect(range(el)).toBe('991–1000 of 1000');
        expect(next().disabled).toBe(true);
        expect(cards(el)).toHaveLength(10);

        // windowed pager never renders 100 buttons
        expect(buttons().length).toBeLessThan(12);
        // 99 page clicks over 1000 friends is slow when the machine is busy.
    }, 30000);

    it('switches straight between filters and back to All', async () => {
        const el = mount();
        await until(() => q(el, '.loading-text') === null);

        qa(el, '.pager .page-btn')[3].click();
        await tick();

        const [all, earned, pending, declined] = qa(el, '.chip');
        expect(all.getAttribute('aria-pressed')).toBe('true');

        earned.click();
        await tick();
        expect(range(el)).toBe('1–10 of 143');
        expect(earned.getAttribute('aria-pressed')).toBe('true');
        expect(all.getAttribute('aria-pressed')).toBe('false');

        // switching goes directly to the other filter
        pending.click();
        await tick();
        expect(range(el)).toBe('1–10 of 779');
        expect(pending.getAttribute('aria-pressed')).toBe('true');
        expect(earned.getAttribute('aria-pressed')).toBe('false');
        expect(all.getAttribute('aria-pressed')).toBe('false');

        declined.click();
        await tick();
        expect(range(el)).toBe('1–10 of 78');
        expect(declined.getAttribute('aria-pressed')).toBe('true');
        expect(pending.getAttribute('aria-pressed')).toBe('false');

        // clicking the one that is on turns it off
        declined.click();
        await tick();
        expect(range(el)).toBe(`1–10 of ${TOTAL}`);
        expect(all.getAttribute('aria-pressed')).toBe('true');

        // clicking All while on a filter clears it
        earned.click();
        await tick();
        all.click();
        await tick();
        expect(range(el)).toBe(`1–10 of ${TOTAL}`);
    });

    it('goes back to page 1 whenever the filter changes', async () => {
        const el = mount();
        await until(() => q(el, '.loading-text') === null);
        qa(el, '.pager .page-btn')[4].click();
        await tick();
        expect(range(el)).toBe(`11–20 of ${TOTAL}`);
        qa(el, '.chip')[1].click();
        await tick();
        expect(range(el)).toBe('1–10 of 143');
    });

    it('resets the filter to All when you search', async () => {
        const el = mount();
        await until(() => q(el, '.loading-text') === null);

        const [all, earned] = qa(el, '.chip');
        earned.click();
        await tick();
        expect(range(el)).toBe('1–10 of 143');

        // Friend 1 has no reward. With the filter left on it would be hidden.
        await typeSearch(el, 'f1@');
        expect(all.getAttribute('aria-pressed')).toBe('true');
        expect(earned.getAttribute('aria-pressed')).toBe('false');
        expect(cards(el)).toHaveLength(1);

        // a filter can still be applied on top of a search afterwards
        earned.click();
        await tick();
        expect(cards(el)).toHaveLength(0);
        all.click();
        await tick();
        expect(cards(el)).toHaveLength(1);
    });

    it('re-renders a thousand friends quickly', async () => {
        const el = mount();
        await until(() => q(el, '.loading-text') === null);
        const start = Date.now();
        for (let i = 0; i < 20; i++) {
            // eslint-disable-next-line no-await-in-loop
            await typeSearch(el, i % 2 ? 'friend' : 'f5');
        }
        const perRender = (Date.now() - start) / 20;
        // generous bound for CI: the point is to catch a quadratic regression
        expect(perRender).toBeLessThan(150);
    });

    it('groups a page by program', async () => {
        const el = mount(40);
        await until(() => q(el, '.loading-text') === null);
        const pills = qa(el, '.program-pill').map((p) => p.textContent.trim());
        expect(new Set(pills)).toEqual(
            new Set(['refer-a-friend', 'member-get-member'])
        );
    });
});
