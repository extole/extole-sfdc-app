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

export function programColors(name) {
    return PALETTE[hashProgram(name)];
}

export function programPillStyle(program) {
    const c = programColors(program);
    return `background:${c.fill};color:${c.primary};`;
}

export function computeInitials(name) {
    if (!name) return '?';
    const trimmed = String(name).trim();
    if (!trimmed) return '?';
    const parts = trimmed.split(/\s+/);
    if (parts.length >= 2) {
        return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return trimmed.substring(0, 2).toUpperCase();
}

export function formatShortDate(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const yy = String(d.getFullYear()).slice(-2);
    return `${mm}/${dd}/${yy}`;
}

// Plain string lists: an LWC cannot pass a list of Apex objects to Apex.
export function detailsArgs(refs) {
    return {
        personIds: (refs || []).map((r) => r.personId),
        programs: (refs || []).map((r) => r.program || '')
    };
}

export function attachRewards(friends, refs) {
    const refById = new Map((refs || []).map((r) => [r.personId, r]));
    return (friends || []).map((f) => {
        const ref = refById.get(f.personId);
        return {
            ...f,
            reward: (ref && ref.reward) || null,
            status: (ref && ref.status) || null
        };
    });
}

// What a reward's state means to a person. Earned in Extole is "earned"; sent or
// fulfilled is "sent".
const REWARD_STATE_WORDS = {
    EARNED: 'earned',
    FULFILLED: 'sent',
    SENT: 'sent',
    REDEEMED: 'redeemed'
};

export function describeReward(f, amountLabel) {
    const status = f.status;
    const earned = status === 'rewarded';
    const declined = status === 'declined';
    const word = earned
        ? REWARD_STATE_WORDS[String(f.reward.state).toUpperCase()] || 'earned'
        : '';
    const amount = earned ? f.reward.amountLabel : amountLabel;
    let text = '';
    if (earned) text = [amount || 'Reward', word].join(' ');
    else if (declined) text = amount ? `${amount} declined` : 'Reward declined';
    else if (status === 'pending' && amount) text = `${amount} pending`;
    return {
        status,
        earned,
        declined,
        text,
        cls: `reward-pill reward-pill-${earned ? 'earned' : declined ? 'declined' : 'pending'}`,
        dateText: earned ? formatShortDate(f.reward.dateEarned) : ''
    };
}

export function decorateFriend(f, amounts) {
    const { status, earned, declined, text, cls, dateText } = describeReward(
        f,
        amounts && amounts[f.program]
    );
    const displayName = f.displayName || f.email || 'Anonymous';
    const milestones = (f.steps || []).map((st) => ({
        key: st.name,
        label: st.label,
        date: st.dateCompleted ? formatShortDate(st.dateCompleted) : null,
        rowClass: st.dateCompleted
            ? 'milestone-row milestone-row-completed'
            : 'milestone-row milestone-row-pending'
    }));
    return {
        key: f.personId,
        program: f.program || 'unknown',
        displayName,
        status,
        sfdcUrl: f.sfdcRecordId
            ? `/lightning/r/${f.sfdcObjectType}/${f.sfdcRecordId}/view`
            : null,
        isLinked: !!f.sfdcRecordId,
        avatarInitials: computeInitials(displayName),
        avatarClass: earned
            ? 'avatar avatar-success'
            : declined
              ? 'avatar avatar-declined'
              : 'avatar avatar-neutral',
        avatarIsEarned: earned,
        avatarIsDeclined: declined,
        rewardStateText: text,
        rewardStateClass: cls,
        rewardDateText: dateText,
        milestones,
        hasMilestones: milestones.length > 0
    };
}

export function groupByProgram(friends, amounts) {
    const byProgram = new Map();
    for (const f of friends) {
        const d = decorateFriend(f, amounts);
        if (!byProgram.has(d.program)) byProgram.set(d.program, []);
        byProgram.get(d.program).push(d);
    }
    return [...byProgram.entries()].map(([program, list]) => ({
        program,
        programStyle: programPillStyle(program),
        friends: list
    }));
}
