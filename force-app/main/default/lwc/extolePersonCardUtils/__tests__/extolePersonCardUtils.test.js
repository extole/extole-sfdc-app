import {
    decorateFriend,
    decorateMilestones,
    describeReward,
    groupByProgram,
    programColors,
    computeInitials
} from 'c/extolePersonCardUtils';

const earnedReward = {
    state: 'EARNED',
    amountLabel: '$50',
    dateEarned: '2026-11-04T12:00:00.000Z'
};

describe('decorateFriend', () => {
    it('shows name, email and an earned reward', () => {
        const d = decorateFriend({
            personId: 'p1',
            displayName: 'Maria Alvarez',
            email: 'maria@example.com',
            program: 'refer-a-friend',
            reward: earnedReward,
            steps: [
                { name: 'a', label: 'Signed Up', dateCompleted: '2026-10-21' }
            ]
        });
        expect(d.displayName).toBe('Maria Alvarez');
        expect(d.email).toBe('maria@example.com');
        expect(d.status).toBe('rewarded');
        expect(d.rewardStateText).toBe('$50 earned');
        expect(d.rewardDateText).toMatch(/^\d\d\/\d\d\/\d\d$/);
        expect(d.avatarIsEarned).toBe(true);
        expect(d.milestones[0].rowClass).toContain('completed');
    });

    it('does not repeat the email when it is already the name', () => {
        const d = decorateFriend({
            personId: 'p1',
            displayName: 'a@example.com',
            email: 'a@example.com'
        });
        expect(d.email).toBeNull();
    });

    it('labels a friend with no name or email by identity value', () => {
        const d = decorateFriend({ personId: 'p1', identityValue: 'M-1001' });
        expect(d.displayName).toBe('M-1001');
        expect(d.email).toBeNull();
        expect(d.searchText).toContain('m-1001');
    });

    it('shows the identity value as a second line when there is a name only', () => {
        const d = decorateFriend({
            personId: 'p1',
            displayName: 'Pat Lee',
            identityValue: 'M-1001'
        });
        expect(d.email).toBe('M-1001');
    });

    it('never renders a blank name', () => {
        expect(decorateFriend({ personId: 'p1' }).displayName).toBe(
            'Unidentified'
        );
    });

    it('marks completed steps that failed quality as failed', () => {
        const d = decorateFriend({
            personId: 'p1',
            steps: [
                {
                    name: 'a',
                    label: 'A',
                    dateCompleted: '2026-10-21',
                    failed: true
                },
                {
                    name: 'b',
                    label: 'B',
                    dateCompleted: '2026-10-22',
                    failed: false
                },
                { name: 'c', label: 'C', dateCompleted: null, failed: false }
            ]
        });
        expect(d.milestones[0].rowClass).toContain('failed');
        expect(d.milestones[1].rowClass).toContain('completed');
        expect(d.milestones[2].rowClass).toContain('pending');
    });

    it('shows a declined friend as declined', () => {
        const d = decorateFriend({ personId: 'p1', status: 'declined' });
        expect(d.status).toBe('declined');
        expect(d.rewardStateText).toBe('Reward declined');
        expect(d.avatarIsDeclined).toBe(true);
        expect(d.avatarIsEarned).toBe(false);
    });

    it('shows a friend with no decision as pending', () => {
        const d = decorateFriend({ personId: 'p1', status: 'pending' });
        expect(d.status).toBe('pending');
        // No decision yet shows nothing on a friend row; the filter still works.
        expect(d.rewardStateText).toBe('');
        expect(d.status).toBe('pending');
        expect(decorateFriend({ personId: 'p2' }).status).toBe('pending');
    });

    it('rewarded wins over a declined status', () => {
        const d = decorateFriend({
            personId: 'p1',
            status: 'declined',
            reward: { state: 'EARNED', amountLabel: '$5' }
        });
        expect(d.status).toBe('rewarded');
    });

    it('handles missing steps and unparseable dates', () => {
        const d = decorateFriend({
            personId: 'p1',
            reward: { state: 'EARNED', amountLabel: '$5', dateEarned: 'nope' },
            steps: undefined
        });
        expect(d.hasMilestones).toBe(false);
        // The pill still shows; a bad date never prints as "Invalid Date".
        expect(d.rewardStateText).toBe('$5 earned');
        expect(d.rewardDateText).toBe('');
    });

    it('is safe against markup in names and emails', () => {
        const d = decorateFriend({
            personId: 'p1',
            displayName: '<img src=x onerror=alert(1)>',
            email: '"><script>x</script>'
        });
        expect(d.displayName).toBe('<img src=x onerror=alert(1)>');
    });
});

describe('groupByProgram', () => {
    it('keeps first-seen order across many programs', () => {
        const friends = [];
        for (let i = 0; i < 30; i++) {
            friends.push(
                decorateFriend({ personId: `p${i}`, program: `prog-${i % 7}` })
            );
        }
        const groups = groupByProgram(friends);
        expect(groups.map((g) => g.program)).toEqual([
            'prog-0',
            'prog-1',
            'prog-2',
            'prog-3',
            'prog-4',
            'prog-5',
            'prog-6'
        ]);
        expect(groups.reduce((n, g) => n + g.friends.length, 0)).toBe(30);
    });

    it('groups a missing program under one bucket', () => {
        const groups = groupByProgram([
            decorateFriend({ personId: 'a' }),
            decorateFriend({ personId: 'b' })
        ]);
        expect(groups).toHaveLength(1);
        expect(groups[0].program).toBe('unknown');
    });
});

describe('helpers', () => {
    it('colors are stable per program name and always defined', () => {
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
});

describe('describeReward', () => {
    it('describes each state as one pill the same way everywhere', () => {
        const rewarded = describeReward({
            reward: { amountLabel: '$5', dateEarned: '2026-11-18T08:21:25' }
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

        const pending = describeReward({}, '$5');
        expect(pending.text).toBe('$5 pending');
        expect(pending.cls).toBe('reward-pill reward-pill-pending');
        expect(pending.dateText).toBe('');
    });

    it('shows nothing for a pending reward with no known amount', () => {
        expect(describeReward({}).text).toBe('');
    });
});

describe('decorateMilestones', () => {
    it('marks done, failed and not-reached steps', () => {
        const rows = decorateMilestones([
            { name: 'a', label: 'A', dateCompleted: '2026-11-18T08:00:00' },
            {
                name: 'b',
                label: 'B',
                dateCompleted: '2026-11-18T09:00:00',
                failed: true
            },
            { name: 'c', label: 'C' }
        ]);
        expect(rows.map((r) => r.rowClass)).toEqual([
            'milestone-row milestone-row-completed',
            'milestone-row milestone-row-failed',
            'milestone-row milestone-row-pending'
        ]);
        expect(rows[0].date).toBe('11/18/26');
        expect(rows[2].date).toBeNull();
        expect(decorateMilestones(undefined)).toEqual([]);
    });
});

describe('reward wording', () => {
    const shown = (state, extra) =>
        describeReward({
            reward: {
                amountLabel: '$5',
                state,
                dateEarned: '2026-11-18T08:00:00',
                ...extra
            }
        });

    it('shows the amount, then how far the reward has got', () => {
        expect(shown('EARNED').text).toBe('$5 earned');
        // Fulfilled in Extole means it has been sent.
        expect(shown('FULFILLED').text).toBe('$5 sent');
        expect(shown('SENT').text).toBe('$5 sent');
        expect(shown('REDEEMED').text).toBe('$5 redeemed');
        expect(shown('EARNED').dateText).toBe('11/18/26');
    });

    it('uses the program amount for a friend with no reward yet', () => {
        const d = decorateFriend(
            { personId: 'p1', program: 'rf' },
            { rf: '$10' }
        );
        expect(d.rewardStateText).toBe('$10 pending');
        expect(
            decorateFriend({ personId: 'p1', program: 'rf' }).rewardStateText
        ).toBe('');
    });

    it('has no date line when there is no date', () => {
        expect(shown('SENT', { dateEarned: undefined }).dateText).toBe('');
    });
});

describe('declined reward amounts', () => {
    it('shows the amount on a declined reward', () => {
        expect(describeReward({ status: 'declined' }, '$5').text).toBe(
            '$5 declined'
        );
        expect(describeReward({ status: 'declined' }, '20%').text).toBe(
            '20% declined'
        );
    });

    it('falls back to the program reward, and only then to plain words', () => {
        const d = decorateFriend(
            { personId: 'p1', program: 'rf', status: 'declined' },
            {},
            { rf: '$5' }
        );
        expect(d.rewardStateText).toBe('$5 declined');
        expect(
            decorateFriend({
                personId: 'p1',
                program: 'rf',
                status: 'declined'
            }).rewardStateText
        ).toBe('Reward declined');
    });

    it('does not guess an amount for a friend with no decision', () => {
        const d = decorateFriend(
            { personId: 'p1', program: 'rf' },
            {},
            { rf: '$5' }
        );
        expect(d.rewardStateText).toBe('');
    });
});
