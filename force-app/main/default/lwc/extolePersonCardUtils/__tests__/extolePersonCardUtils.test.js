import {
    programColors,
    computeInitials,
    formatShortDate,
    describeReward,
    decorateFriend,
    groupByProgram,
    detailsArgs,
    attachRewards
} from 'c/extolePersonCardUtils';

describe('helpers', () => {
    it('colors are stable per program and always defined', () => {
        for (const name of ['', null, 'a', 'refer-a-friend', 'x'.repeat(500)]) {
            expect(programColors(name)).toBeDefined();
            expect(programColors(name)).toBe(programColors(name));
        }
    });

    it('initials handle odd names', () => {
        expect(computeInitials('')).toBe('?');
        expect(computeInitials('   ')).toBe('?');
        expect(computeInitials('Maria Alvarez')).toBe('MA');
        expect(computeInitials('Cher')).toBe('CH');
    });

    it('dates are short, and bad ones are blank', () => {
        expect(formatShortDate('2026-11-18T08:00:00')).toBe('11/18/26');
        expect(formatShortDate('nope')).toBe('');
        expect(formatShortDate(null)).toBe('');
    });
});

describe('describeReward', () => {
    it('describes each state as one pill the same way everywhere', () => {
        const rewarded = describeReward({
            status: 'rewarded',
            reward: {
                state: 'EARNED',
                amountLabel: '$5',
                dateEarned: '2026-11-18T08:21:25'
            }
        });
        expect(rewarded.status).toBe('rewarded');
        expect(rewarded.text).toBe('$5 earned');
        expect(rewarded.cls).toBe('reward-pill reward-pill-earned');
        expect(rewarded.dateText).toBe('11/18/26');

        expect(describeReward({ status: 'declined' }).text).toBe(
            'Reward declined'
        );
        const declined = describeReward({ status: 'declined' }, '$5');
        expect(declined.text).toBe('$5 declined');
        expect(declined.cls).toBe('reward-pill reward-pill-declined');

        const pending = describeReward({ status: 'pending' }, '$5');
        expect(pending.text).toBe('$5 pending');
        expect(pending.cls).toBe('reward-pill reward-pill-pending');
        expect(pending.dateText).toBe('');
    });

    it('says earned, sent or redeemed to match the reward state', () => {
        const text = (state) =>
            describeReward({
                status: 'rewarded',
                reward: { state, amountLabel: '$5' }
            }).text;
        expect(text('EARNED')).toBe('$5 earned');
        expect(text('FULFILLED')).toBe('$5 sent');
        expect(text('SENT')).toBe('$5 sent');
        expect(text('REDEEMED')).toBe('$5 redeemed');
    });

    it('shows nothing for a pending reward with no known amount', () => {
        expect(describeReward({ status: 'pending' }).text).toBe('');
    });

    it('shows nothing when the status is unknown, even with an amount', () => {
        expect(describeReward({ status: null }, '$5').text).toBe('');
    });

    it('handles a percent and an amount with no label', () => {
        expect(describeReward({ status: 'declined' }, '20%').text).toBe(
            '20% declined'
        );
        expect(
            describeReward({ status: 'rewarded', reward: { state: 'EARNED' } })
                .text
        ).toBe('Reward earned');
    });
});

describe('decorateFriend', () => {
    it('shows an earned reward as a pill with its date', () => {
        const d = decorateFriend({
            personId: 'p1',
            displayName: 'Maria Alvarez',
            program: 'refer-a-friend',
            status: 'rewarded',
            reward: {
                state: 'EARNED',
                amountLabel: '$50',
                dateEarned: '2026-11-18T08:00:00'
            },
            steps: [
                { name: 'a', label: 'Signed Up', dateCompleted: '2026-10-21' }
            ]
        });
        expect(d.rewardStateText).toBe('$50 earned');
        expect(d.rewardDateText).toBe('11/18/26');
        expect(d.status).toBe('rewarded');
        expect(d.avatarIsEarned).toBe(true);
        expect(d.milestones[0].rowClass).toContain('completed');
    });

    it('shows nothing for a friend with no decision and no known amount', () => {
        const d = decorateFriend({
            personId: 'p1',
            email: 'a@example.com',
            status: 'pending'
        });
        expect(d.rewardStateText).toBe('');
        expect(d.displayName).toBe('a@example.com');
        expect(d.program).toBe('unknown');
        expect(d.status).toBe('pending');
        expect(d.hasMilestones).toBe(false);
    });

    it('uses what the program pays for a friend still pending', () => {
        const d = decorateFriend(
            { personId: 'p1', program: 'rf', status: 'pending' },
            { rf: '$10' }
        );
        expect(d.rewardStateText).toBe('$10 pending');
    });

    it('marks a declined friend, using the advocate amount if known', () => {
        const d = decorateFriend(
            { personId: 'p1', program: 'rf', status: 'declined' },
            { rf: '$5' }
        );
        expect(d.rewardStateText).toBe('$5 declined');
        expect(d.avatarIsDeclined).toBe(true);
        expect(
            decorateFriend({ personId: 'p1', status: 'declined' })
                .rewardStateText
        ).toBe('Reward declined');
    });

    it('does not guess a status for a friend whose status is unknown', () => {
        const d = decorateFriend(
            { personId: 'p1', program: 'rf', status: null },
            { rf: '$5' }
        );
        expect(d.rewardStateText).toBe('');
        expect(d.status).toBeNull();
    });

    it('links to the Salesforce record when there is one', () => {
        const d = decorateFriend({
            personId: 'p1',
            sfdcRecordId: '003x',
            sfdcObjectType: 'Contact'
        });
        expect(d.sfdcUrl).toBe('/lightning/r/Contact/003x/view');
        expect(d.isLinked).toBe(true);
    });
});

describe('groupByProgram', () => {
    it('groups friends under their program in first-seen order', () => {
        const groups = groupByProgram([
            { personId: 'a', program: 'one' },
            { personId: 'b', program: 'two' },
            { personId: 'c', program: 'one' }
        ]);
        expect(groups.map((g) => g.program)).toEqual(['one', 'two']);
        expect(groups[0].friends.map((f) => f.key)).toEqual(['a', 'c']);
    });

    it('passes the amounts down to each friend', () => {
        const [g] = groupByProgram(
            [{ personId: 'a', program: 'one', status: 'pending' }],
            { one: '$7' }
        );
        expect(g.friends[0].rewardStateText).toBe('$7 pending');
    });
});

describe('detailsArgs', () => {
    it('turns references into two plain lists that line up', () => {
        expect(
            detailsArgs([
                {
                    personId: 'p1',
                    program: 'one',
                    reward: { amountLabel: '$5' }
                },
                { personId: 'p2' }
            ])
        ).toEqual({ personIds: ['p1', 'p2'], programs: ['one', ''] });
        expect(detailsArgs(undefined)).toEqual({ personIds: [], programs: [] });
    });
});

describe('attachRewards', () => {
    it('puts each reference reward back on its friend', () => {
        const refs = [
            {
                personId: 'p1',
                reward: { amountLabel: '$5' },
                status: 'rewarded'
            },
            { personId: 'p2', reward: null, status: 'declined' }
        ];
        const out = attachRewards(
            [{ personId: 'p1' }, { personId: 'p2' }, { personId: 'p3' }],
            refs
        );
        expect(out[0].reward).toEqual({ amountLabel: '$5' });
        expect(out[0].status).toBe('rewarded');
        expect(out[1].reward).toBeNull();
        expect(out[1].status).toBe('declined');
        expect(out[2].reward).toBeNull();
        expect(out[2].status).toBeNull();
    });
});
