const PALETTE = [
    { primary: '#1D9E75', fill: 'rgba(29, 158, 117, 0.12)' },
    { primary: '#2563EB', fill: 'rgba(37, 99, 235, 0.10)' },
    { primary: '#8B5CF6', fill: 'rgba(139, 92, 246, 0.10)' },
    { primary: '#F97316', fill: 'rgba(249, 115, 22, 0.12)' },
    { primary: '#E94560', fill: 'rgba(233, 69, 96, 0.10)' }
];

export const FRIENDS_HELP_TEXT =
    "People this person referred. They only show up once identified, for example by email. Green steps counted, red failed Extole's checks, hollow haven't happened yet.";

export const REFERRED_BY_HELP_TEXT =
    "Who referred this person, and how far they got. Green steps counted, red failed Extole's checks, hollow haven't happened yet.";

export const OFFERS_HELP_TEXT =
    "Offers this person is in that aren't referrals, and how far they got. Green steps counted, red failed Extole's checks, hollow haven't happened yet.";

function hashProgram(name) {
    if (!name) return 0;
    let h = 0;
    for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) | 0;
    return Math.abs(h) % PALETTE.length;
}

export function programColors(name) {
    return PALETTE[hashProgram(name)];
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

export function programPillStyle(program) {
    const c = programColors(program);
    return `background:${c.fill};color:${c.primary};`;
}

// Turns a friend from Apex into everything the friend card renders.
// Where a friend's reward stands: 'rewarded', 'declined' or 'pending'.
// Apex decides it; a friend with a reward is always rewarded.
export function rewardStatus(f) {
    if (f.reward) return 'rewarded';
    return f.status === 'declined' ? 'declined' : 'pending';
}

// A person's steps as rows for the milestone list.
export function decorateMilestones(steps) {
    return (steps || []).map((s) => ({
        key: s.name,
        label: s.label,
        date: s.dateCompleted ? formatShortDate(s.dateCompleted) : null,
        rowClass: !s.dateCompleted
            ? 'milestone-row milestone-row-pending'
            : s.failed
              ? 'milestone-row milestone-row-failed'
              : 'milestone-row milestone-row-completed'
    }));
}

// What a reward's state means to a person on the phone. Earned in Extole is
// "earned"; sent or fulfilled is "sent".
const REWARD_STATE_WORDS = {
    EARNED: 'earned',
    FULFILLED: 'sent',
    SENT: 'sent',
    REDEEMED: 'redeemed'
};

// How a reward is shown: one pill with the amount and where it stands, such as
// "$5 pending", "$5 earned", "$5 sent" or "$5 declined", and the date beneath
// once it is earned. amountLabel is what the program pays, for a reward that
// has no row yet. Without any amount, a pending reward shows nothing.
export function describeReward(f, amountLabel, declinedLabel) {
    const status = rewardStatus(f);
    const earned = status === 'rewarded';
    const declined = status === 'declined';
    const word = earned
        ? REWARD_STATE_WORDS[String(f.reward.state).toUpperCase()] || 'earned'
        : '';
    const amount = earned ? f.reward.amountLabel : amountLabel;
    let text = '';
    if (earned) text = [amount || 'Reward', word].join(' ');
    else if (declined) {
        // A decline falls back to the program's one reward when the amount is
        // otherwise unknown.
        const shown = amount || declinedLabel;
        text = shown ? `${shown} declined` : 'Reward declined';
    } else if (amount) text = `${amount} pending`;
    return {
        status,
        earned,
        declined,
        text,
        cls: `reward-pill reward-pill-${earned ? 'earned' : declined ? 'declined' : 'pending'}`,
        dateText: earned ? formatShortDate(f.reward.dateEarned) : ''
    };
}

export function decorateFriend(f, amounts, declinedAmounts) {
    const { status, earned, declined, text, cls, dateText } = describeReward(
        f,
        amounts && amounts[f.program],
        declinedAmounts && declinedAmounts[f.program]
    );
    const displayName =
        f.displayName || f.email || f.identityValue || 'Unidentified';
    // Second line: the email, or for accounts keyed on something else (a member
    // number, say) the identity value, when it is not already the name shown.
    const secondary = f.email || f.identityValue;
    const milestones = decorateMilestones(f.steps);
    return {
        key: f.personId,
        program: f.program || 'unknown',
        displayName,
        email: secondary && secondary !== displayName ? secondary : null,
        searchText:
            `${displayName} ${f.email || ''} ${f.identityValue || ''}`.toLowerCase(),
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
        // Nothing shows until there is an amount, a reward or a decline; the
        // filter still finds a friend with no decision yet.
        rewardStateText: text,
        rewardStateClass: cls,
        rewardDateText: dateText,
        milestones,
        hasMilestones: milestones.length > 0
    };
}

// Groups decorated friends by program, keeping first-seen order.
export function groupByProgram(decorated) {
    const byProgram = new Map();
    for (const f of decorated) {
        if (!byProgram.has(f.program)) byProgram.set(f.program, []);
        byProgram.get(f.program).push(f);
    }
    const groups = [];
    for (const [program, friends] of byProgram.entries()) {
        groups.push({
            program,
            programStyle: programPillStyle(program),
            friends
        });
    }
    return groups;
}
