public with sharing class ExtolePersonCardController {
    // Friends loaded on the card's first request. Each friend costs 2 or 3 sequential callouts
    // (profile when needed, data, steps), roughly a second per friend in practice, and one Apex
    // transaction allows 100 callouts, so friends load in batches rather than all at once.
    @TestVisible
    private static final Integer FRIEND_BATCH = 5;
    private static final Integer PAGE_SIZE = 100;
    private static final Integer MAX_PAGES = 10;
    private static final Integer CALLOUTS_PER_FRIEND = 3;
    private static final Integer CALLOUTS_PER_FRIEND_IDENTIFIED = 2;
    private static final Long MAX_ELAPSED_MS = 90000;
    private static final Long START_MS = System.currentTimeMillis();
    // Reward states that mean the advocate got the reward, or will.
    private static final Set<String> REWARDED_STATES = new Set<String>{
        'EARNED',
        'FULFILLED',
        'SENT',
        'REDEEMED'
    };
    // Reward states that mean the reward did not go out.
    private static final Set<String> DECLINED_STATES = new Set<String>{
        'FAILED',
        'CANCELED',
        'REVOKED'
    };
    private static final Integer MAX_DECISION_PAGES = 3;
    private static final Integer MAX_REFERRERS = 50;
    private static final Integer MAX_OWN_PROGRAMS = 4;
    @TestVisible
    private static final String PROFILE_URL_BASE = 'https://my.extole.com/profiles/view/';

    @AuraEnabled(cacheable=true)
    public static ExtolePersonCard.CardData getCardData(String email) {
        ExtolePersonCard.CardData result = new ExtolePersonCard.CardData();
        result.email = email;
        if (String.isBlank(email))
            return result;

        try {
            ExtoleConfig config = new ExtoleConfig('Extole_API');
            ExtoleClient client = new ExtoleClient();

            Map<String, Object> person = lookupPerson(config, client, email);
            if (person == null)
                return result;
            String personId = (String) person.get('id');
            result.profileUrl = profileUrl(
                personId,
                fetchClientId(config, client)
            );
            // Only accounts keyed on email can safely drop anonymous people on the server.
            // For any other identity key an identified friend may have no key value yet.
            Boolean emailKeyed = 'email'.equals(person.get('identity_key'));

            result.shareLinks = fetchShareLinks(config, client, personId);

            List<Map<String, Object>> rels = fetchRelationships(
                config,
                client,
                personId,
                emailKeyed
            );
            Set<String> declinedFriendIds = new Set<String>();
            Map<String, ExtolePersonCard.Reward> ownRewardByProgram = new Map<String, ExtolePersonCard.Reward>();
            Map<String, Boolean> ownDeclinedByProgram = new Map<String, Boolean>();
            Map<String, ExtolePersonCard.Reward> rewardsByFriendId = fetchRewards(
                config,
                client,
                personId,
                declinedFriendIds,
                ownRewardByProgram,
                ownDeclinedByProgram
            );
            addDeclinedEvaluations(
                config,
                client,
                personId,
                declinedFriendIds,
                ownDeclinedByProgram
            );

            Set<String> seenFriendIds = new Set<String>();
            Set<String> seenReferrers = new Set<String>();
            Map<String, String> personIdToProgram = new Map<String, String>();
            Map<String, String> identityKeyById = new Map<String, String>();
            Map<String, String> identityValueById = new Map<String, String>();

            for (Map<String, Object> rel : rels) {
                String role = getString(rel, 'my_role');
                String otherId = getString(rel, 'other_person_id');
                if (otherId == null)
                    continue;
                String idKey = otherIdentity(rel, 'identity_key');
                String idValue = otherIdentity(rel, 'identity_key_value');

                if (role == 'ADVOCATE' && !seenFriendIds.contains(otherId)) {
                    seenFriendIds.add(otherId);
                    ExtolePersonCard.FriendRef ref = new ExtolePersonCard.FriendRef();
                    ref.personId = otherId;
                    ref.program = getString(rel, 'program');
                    ref.identityKey = idKey;
                    ref.identityValue = idValue;
                    ref.reward = rewardsByFriendId.get(otherId);
                    ref.status = rewardStatus(
                        ref.reward,
                        declinedFriendIds.contains(otherId)
                    );
                    result.friendRefs.add(ref);
                } else if (
                    role == 'FRIEND' &&
                    result.referrers.size() < MAX_REFERRERS &&
                    seenReferrers.add(otherId + '|' + getString(rel, 'program'))
                ) {
                    ExtolePersonCard.ReferredBy rb = new ExtolePersonCard.ReferredBy();
                    rb.personId = otherId;
                    rb.program = getString(rel, 'program');
                    rb.referredDate = getString(rel, 'created_date');
                    rb.identityValue = idValue;
                    if ('email'.equals(idKey))
                        rb.email = idValue;
                    result.referrers.add(rb);
                    if (result.referredBy == null)
                        result.referredBy = rb;
                    identityKeyById.put(otherId, idKey);
                    identityValueById.put(otherId, idValue);
                }
            }
            result.totalFriends = result.friendRefs.size();
            // Load the referrer and the first batch of friends. Everyone else loads on demand.
            List<String> idsToLoad = new List<String>();
            Set<String> friendPrograms = new Set<String>();
            // Only the first batch of referrers is looked up by name; the rest
            // show the email already on the relationship.
            Integer referrerNamesLoaded = 0;
            for (ExtolePersonCard.ReferredBy rb : result.referrers) {
                if (referrerNamesLoaded >= FRIEND_BATCH)
                    break;
                referrerNamesLoaded++;
                if (!personIdToProgram.containsKey(rb.personId))
                    idsToLoad.add(rb.personId);
                personIdToProgram.put(rb.personId, rb.program);
            }
            Integer firstBatch = Math.min(
                FRIEND_BATCH,
                result.friendRefs.size()
            );
            for (Integer i = 0; i < firstBatch; i++) {
                ExtolePersonCard.FriendRef ref = result.friendRefs[i];
                idsToLoad.add(ref.personId);
                personIdToProgram.put(ref.personId, ref.program);
                identityKeyById.put(ref.personId, ref.identityKey);
                identityValueById.put(ref.personId, ref.identityValue);
                if (String.isNotBlank(ref.program))
                    friendPrograms.add(ref.program);
            }

            Set<String> attempted = new Set<String>();
            Map<String, PersonProfile> profileById = loadProfiles(
                config,
                client,
                idsToLoad,
                personIdToProgram,
                identityKeyById,
                identityValueById,
                friendPrograms,
                attempted
            );

            for (Integer i = 0; i < firstBatch; i++) {
                ExtolePersonCard.FriendRef ref = result.friendRefs[i];
                if (!attempted.contains(ref.personId))
                    break;
                ExtolePersonCard.Friend f = new ExtolePersonCard.Friend();
                f.personId = ref.personId;
                f.program = ref.program;
                f.identityValue = ref.identityValue;
                f.reward = ref.reward;
                f.status = ref.status;
                applyProfile(f, profileById.get(ref.personId));
                result.friends.add(f);
            }
            for (ExtolePersonCard.ReferredBy rb : result.referrers) {
                PersonProfile profile = profileById.get(rb.personId);
                if (profile != null) {
                    rb.email = profile.email;
                    rb.displayName = String.isNotBlank(profile.displayName)
                        ? profile.displayName
                        : profile.email;
                }
                if (String.isBlank(rb.displayName))
                    rb.displayName = rb.identityValue;
            }

            // Offers that aren't a referral have their own card.
            Set<String> referralPrograms = new Set<String>();
            for (ExtolePersonCard.ReferredBy rb : result.referrers) {
                referralPrograms.add(
                    String.isBlank(rb.program) ? '' : rb.program
                );
            }
            for (String key : new List<String>(ownRewardByProgram.keySet())) {
                if (!referralPrograms.contains(key))
                    ownRewardByProgram.remove(key);
            }
            for (String key : new List<String>(ownDeclinedByProgram.keySet())) {
                if (!referralPrograms.contains(key))
                    ownDeclinedByProgram.remove(key);
            }
            result.ownPrograms = buildOwnPrograms(
                config,
                client,
                personId,
                result.referrers,
                ownRewardByProgram,
                ownDeclinedByProgram,
                new List<String>()
            );
            attributeRewardsToReferrers(
                config,
                client,
                personId,
                result.ownPrograms,
                result.referrers
            );

            Set<String> amountPrograms = new Set<String>();
            for (ExtolePersonCard.FriendRef ref : result.friendRefs) {
                if (String.isNotBlank(ref.program))
                    amountPrograms.add(ref.program);
            }
            for (ExtolePersonCard.ReferredBy rb : result.referrers) {
                if (String.isNotBlank(rb.program))
                    amountPrograms.add(rb.program);
            }
            Map<String, ProgramAmounts> amounts = fetchProgramAmounts(
                config,
                client,
                amountPrograms
            );
            for (String program : amounts.keySet()) {
                if (amounts.get(program).advocate != null)
                    result.advocateAmounts.put(
                        program,
                        amounts.get(program).advocate
                    );
                if (amounts.get(program).own != null)
                    result.ownAmounts.put(program, amounts.get(program).own);
                if (amounts.get(program).only != null)
                    result.onlyAmounts.put(program, amounts.get(program).only);
            }

            result.hasAnyData =
                !result.shareLinks.isEmpty() ||
                !result.friendRefs.isEmpty() ||
                !result.referrers.isEmpty() ||
                !result.ownPrograms.isEmpty();

            List<String> emails = collectEmails(result);
            if (!emails.isEmpty()) {
                applySfdcLinks(result, attachSfdcLinks(emails));
            }
        } catch (Exception e) {
            System.debug(
                'ExtolePersonCardController.getCardData ERROR: ' +
                e.getMessage()
            );
        }
        return result;
    }

    // The offers a person is in that aren't a referral: the program the person
    // was never referred into, with their steps and reward in it. A referral
    // program shows on the person card instead.
    @AuraEnabled(cacheable=true)
    public static ExtolePersonCard.OffersData getOffersData(String email) {
        ExtolePersonCard.OffersData result = new ExtolePersonCard.OffersData();
        result.email = email;
        if (String.isBlank(email))
            return result;
        try {
            ExtoleConfig config = new ExtoleConfig('Extole_API');
            ExtoleClient client = new ExtoleClient();
            Map<String, Object> person = lookupPerson(config, client, email);
            if (person == null)
                return result;
            String personId = (String) person.get('id');
            result.profileUrl = profileUrl(
                personId,
                fetchClientId(config, client)
            );

            Set<String> referralPrograms = fetchReferralPrograms(
                config,
                client,
                personId
            );
            Map<String, ExtolePersonCard.Reward> rewardByProgram = new Map<String, ExtolePersonCard.Reward>();
            Map<String, Boolean> declinedByProgram = new Map<String, Boolean>();
            fetchRewards(
                config,
                client,
                personId,
                new Set<String>(),
                rewardByProgram,
                declinedByProgram
            );
            addDeclinedEvaluations(
                config,
                client,
                personId,
                new Set<String>(),
                declinedByProgram
            );
            for (String key : new List<String>(rewardByProgram.keySet())) {
                if (referralPrograms.contains(key))
                    rewardByProgram.remove(key);
            }
            for (String key : new List<String>(declinedByProgram.keySet())) {
                if (referralPrograms.contains(key))
                    declinedByProgram.remove(key);
            }
            result.programs = buildOwnPrograms(
                config,
                client,
                personId,
                new List<ExtolePersonCard.ReferredBy>(),
                rewardByProgram,
                declinedByProgram,
                fetchParticipantPrograms(
                    config,
                    client,
                    personId,
                    referralPrograms
                )
            );
            Set<String> amountPrograms = new Set<String>();
            for (ExtolePersonCard.OwnProgram op : result.programs) {
                if (String.isNotBlank(op.program))
                    amountPrograms.add(op.program);
            }
            Map<String, ProgramAmounts> amounts = fetchProgramAmounts(
                config,
                client,
                amountPrograms
            );
            for (String program : amounts.keySet()) {
                if (amounts.get(program).own != null)
                    result.ownAmounts.put(program, amounts.get(program).own);
            }
            result.hasAnyData = !result.programs.isEmpty();
        } catch (Exception e) {
            System.debug(
                'ExtolePersonCardController.getOffersData ERROR: ' +
                e.getMessage()
            );
        }
        return result;
    }

    // Programs that referred this person. Blank stands for a referral with no program.
    private static Set<String> fetchReferralPrograms(
        ExtoleConfig config,
        ExtoleClient client,
        String personId
    ) {
        Set<String> out = new Set<String>();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            config.getEndpoint() +
                ExtoleConstants.PEOPLE_PATH +
                '/' +
                personId +
                '/relationships?my_roles=FRIEND&limit=100'
        );
        req.setMethod('GET');
        if (!config.isNamedCredentialMode())
            req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);
        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
            return out;
        Object parsed = JSON.deserializeUntyped(res.getBody());
        if (!(parsed instanceof List<Object>))
            return out;
        for (Object o : (List<Object>) parsed) {
            if (!(o instanceof Map<String, Object>))
                continue;
            String program = getString((Map<String, Object>) o, 'program');
            out.add(String.isBlank(program) ? '' : program);
        }
        return out;
    }

    // Programs this person has taken part in as a participant, from their
    // steps, so an offer shows even before any reward is decided.
    private static List<String> fetchParticipantPrograms(
        ExtoleConfig config,
        ExtoleClient client,
        String personId,
        Set<String> skip
    ) {
        List<String> out = new List<String>();
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(
                config.getEndpoint() +
                    ExtoleConstants.PEOPLE_PATH +
                    '/' +
                    personId +
                    '/steps?journey_names=PARTICIPANT&is_primary=true&limit=100'
            );
            req.setMethod('GET');
            if (!config.isNamedCredentialMode())
                req.setHeader('Authorization', config.getAuthHeader());
            req.setTimeout(config.timeoutMs);
            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
                return out;
            Object parsed = JSON.deserializeUntyped(res.getBody());
            if (!(parsed instanceof List<Object>))
                return out;
            Set<String> seen = new Set<String>();
            for (Object o : (List<Object>) parsed) {
                if (!(o instanceof Map<String, Object>))
                    continue;
                String key = programKey((Map<String, Object>) o);
                if (!skip.contains(key) && seen.add(key))
                    out.add(key);
            }
        } catch (Exception e) {
            System.debug('fetchParticipantPrograms ERROR: ' + e.getMessage());
        }
        return out;
    }

    private class ProgramAmounts {
        String advocate;
        String own;
        // The program's only reward, when it has just the one unnamed.
        String only;
    }

    // "$5", "$12.50", "£10", "20%", "500 points": a face value as a person
    // reads it.
    private static String formatAmount(
        Decimal faceValue,
        String faceValueType
    ) {
        Map<String, String> symbols = new Map<String, String>{
            'usd' => '$',
            'cad' => 'CA$',
            'aud' => 'A$',
            'gbp' => '£',
            'eur' => '€',
            'jpy' => '¥'
        };
        String typeKey = faceValueType == null
            ? ''
            : faceValueType.toLowerCase();
        // Whole numbers lose their decimals; anything else keeps two.
        Decimal whole = faceValue.setScale(0, System.RoundingMode.HALF_UP);
        String num = faceValue == whole
            ? String.valueOf(whole)
            : String.valueOf(
                  faceValue.setScale(2, System.RoundingMode.HALF_UP)
              );
        if (typeKey.contains('percent'))
            return num + '%';
        if (symbols.containsKey(typeKey))
            return symbols.get(typeKey) + num;
        if (typeKey == 'points')
            return num + ' points';
        return String.isBlank(faceValueType)
            ? num
            : num + ' ' + faceValueType.toUpperCase();
    }

    // What each program pays, from its reward setup, so a reward with no row
    // yet can still show an amount. Programs whose reward can't be worked out
    // are left out, and the card then shows no amount rather than a guess.
    private static Map<String, ProgramAmounts> fetchProgramAmounts(
        ExtoleConfig config,
        ExtoleClient client,
        Set<String> programs
    ) {
        Map<String, ProgramAmounts> out = new Map<String, ProgramAmounts>();
        if (
            programs.isEmpty() ||
            Limits.getCallouts() + 3 > Limits.getLimitCallouts()
        )
            return out;
        try {
            Map<String, String> supplierAmounts = fetchSupplierAmounts(
                config,
                client
            );
            if (supplierAmounts.isEmpty())
                return out;
            Map<String, String> campaigns = fetchProgramCampaigns(
                config,
                client,
                programs
            );
            for (String program : campaigns.keySet()) {
                if (Limits.getCallouts() >= Limits.getLimitCallouts())
                    break;
                ProgramAmounts pa = fetchCampaignAmounts(
                    config,
                    client,
                    campaigns.get(program),
                    supplierAmounts
                );
                if (pa != null)
                    out.put(program, pa);
            }
        } catch (Exception e) {
            System.debug('fetchProgramAmounts ERROR: ' + e.getMessage());
        }
        return out;
    }

    private static HttpRequest getRequest(ExtoleConfig config, String path) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + path);
        req.setMethod('GET');
        if (!config.isNamedCredentialMode())
            req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);
        return req;
    }

    private static Map<String, String> fetchSupplierAmounts(
        ExtoleConfig config,
        ExtoleClient client
    ) {
        Map<String, String> out = new Map<String, String>();
        HttpResponse res = client.send(
            config,
            getRequest(config, '/v6/reward-suppliers')
        );
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
            return out;
        Object parsed = JSON.deserializeUntyped(res.getBody());
        if (!(parsed instanceof List<Object>))
            return out;
        for (Object o : (List<Object>) parsed) {
            if (!(o instanceof Map<String, Object>))
                continue;
            Map<String, Object> m = (Map<String, Object>) o;
            Object fv = m.get('face_value');
            String id = getString(m, 'id');
            if (id == null || fv == null)
                continue;
            try {
                out.put(
                    id,
                    formatAmount(
                        Decimal.valueOf(String.valueOf(fv)),
                        getString(m, 'face_value_type')
                    )
                );
            } catch (Exception ignored) {
            }
        }
        return out;
    }

    // Program label to its campaign id, preferring the live one.
    private static Map<String, String> fetchProgramCampaigns(
        ExtoleConfig config,
        ExtoleClient client,
        Set<String> programs
    ) {
        Map<String, String> out = new Map<String, String>();
        HttpResponse res = client.send(
            config,
            getRequest(config, ExtoleConstants.CAMPAIGNS_SUMMARY_PATH)
        );
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
            return out;
        Object parsed = JSON.deserializeUntyped(res.getBody());
        if (!(parsed instanceof List<Object>))
            return out;
        for (Object o : (List<Object>) parsed) {
            if (!(o instanceof Map<String, Object>))
                continue;
            Map<String, Object> c = (Map<String, Object>) o;
            String prog = getString(c, 'program_label');
            String cid = getString(c, 'campaign_id');
            if (!programs.contains(prog) || cid == null)
                continue;
            if (!out.containsKey(prog) || 'LIVE'.equals(getString(c, 'state')))
                out.put(prog, cid);
        }
        return out;
    }

    // The advocate's reward is the one named for the advocate; a person's own
    // is the friend or participant one, or the only reward when it's unnamed.
    private static ProgramAmounts fetchCampaignAmounts(
        ExtoleConfig config,
        ExtoleClient client,
        String campaignId,
        Map<String, String> supplierAmounts
    ) {
        HttpResponse res = client.send(
            config,
            getRequest(
                config,
                ExtoleConstants.CAMPAIGNS_PATH +
                    '/' +
                    campaignId +
                    '/components'
            )
        );
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
            return null;
        Object parsed = JSON.deserializeUntyped(res.getBody());
        if (!(parsed instanceof List<Object>))
            return null;
        ProgramAmounts pa = new ProgramAmounts();
        List<String> unnamed = new List<String>();
        for (Object o : (List<Object>) parsed) {
            if (!(o instanceof Map<String, Object>))
                continue;
            Map<String, Object> comp = (Map<String, Object>) o;
            Object typesRaw = comp.get('types');
            if (
                !(typesRaw instanceof List<Object>) ||
                !((List<Object>) typesRaw).contains('reward-v10.0')
            )
                continue;
            String amount = supplierAmounts.get(rewardSupplierId(comp));
            if (amount == null)
                continue;
            String name = (getString(comp, 'name') + '').toLowerCase();
            if (name.contains('advocate')) {
                if (pa.advocate == null)
                    pa.advocate = amount;
            } else if (
                name.contains('friend') || name.contains('participant')
            ) {
                if (pa.own == null)
                    pa.own = amount;
            } else {
                unnamed.add(amount);
            }
        }
        if (pa.own == null && pa.advocate == null && unnamed.size() == 1) {
            pa.own = unnamed[0];
            pa.only = unnamed[0];
        }
        return pa.advocate == null && pa.own == null ? null : pa;
    }

    // The supplier a reward component is set to, from its settings.
    private static String rewardSupplierId(Map<String, Object> comp) {
        Object varsRaw = comp.get('variables');
        if (!(varsRaw instanceof List<Object>))
            return null;
        for (Object v : (List<Object>) varsRaw) {
            if (!(v instanceof Map<String, Object>))
                continue;
            Map<String, Object> variable = (Map<String, Object>) v;
            if (!'rewardSupplierId'.equals(getString(variable, 'name')))
                continue;
            Object values = variable.get('values');
            if (values instanceof Map<String, Object>) {
                Object d = ((Map<String, Object>) values).get('default');
                return d instanceof String ? (String) d : null;
            }
        }
        return null;
    }

    // Loads details for the next batch of friends. The card and the expanded view call this
    // repeatedly; each call is its own transaction with a fresh callout budget. The four lists
    // line up by position. Returns friends in the order requested, stopping early if the callout
    // budget runs out, so callers should advance by the number returned, not the number requested.
    @AuraEnabled(cacheable=true)
    public static List<ExtolePersonCard.Friend> getFriendDetails(
        List<String> personIds,
        List<String> programs,
        List<String> identityKeys,
        List<String> identityValues
    ) {
        List<ExtolePersonCard.Friend> out = new List<ExtolePersonCard.Friend>();
        if (personIds == null || personIds.isEmpty())
            return out;

        try {
            ExtoleConfig config = new ExtoleConfig('Extole_API');
            ExtoleClient client = new ExtoleClient();

            Map<String, String> personIdToProgram = new Map<String, String>();
            Map<String, String> identityKeyById = new Map<String, String>();
            Map<String, String> identityValueById = new Map<String, String>();
            Set<String> friendPrograms = new Set<String>();
            for (Integer i = 0; i < personIds.size(); i++) {
                String program = valueAt(programs, i);
                personIdToProgram.put(personIds[i], program);
                identityKeyById.put(personIds[i], valueAt(identityKeys, i));
                identityValueById.put(personIds[i], valueAt(identityValues, i));
                if (String.isNotBlank(program))
                    friendPrograms.add(program);
            }

            Set<String> attempted = new Set<String>();
            Map<String, PersonProfile> profileById = loadProfiles(
                config,
                client,
                personIds,
                personIdToProgram,
                identityKeyById,
                identityValueById,
                friendPrograms,
                attempted
            );

            for (String pid : personIds) {
                if (!attempted.contains(pid))
                    break;
                ExtolePersonCard.Friend f = new ExtolePersonCard.Friend();
                f.personId = pid;
                f.program = personIdToProgram.get(pid);
                f.identityValue = identityValueById.get(pid);
                applyProfile(f, profileById.get(pid));
                out.add(f);
            }

            List<String> emails = new List<String>();
            for (ExtolePersonCard.Friend f : out) {
                if (String.isNotBlank(f.email))
                    emails.add(f.email);
            }
            if (!emails.isEmpty()) {
                Map<String, ExtolePersonCard.SfdcLink> byEmail = new Map<String, ExtolePersonCard.SfdcLink>();
                for (ExtolePersonCard.SfdcLink l : attachSfdcLinks(emails)) {
                    if (l.email != null)
                        byEmail.put(l.email.toLowerCase(), l);
                }
                for (ExtolePersonCard.Friend f : out) {
                    if (f.email == null)
                        continue;
                    ExtolePersonCard.SfdcLink l = byEmail.get(
                        f.email.toLowerCase()
                    );
                    if (l != null) {
                        f.sfdcRecordId = l.recordId;
                        f.sfdcObjectType = l.objectType;
                    }
                }
            }
        } catch (Exception e) {
            System.debug(
                'ExtolePersonCardController.getFriendDetails ERROR: ' +
                e.getMessage()
            );
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<ExtolePersonCard.SfdcLink> attachSfdcLinks(
        List<String> emails
    ) {
        List<ExtolePersonCard.SfdcLink> out = new List<ExtolePersonCard.SfdcLink>();
        if (emails == null || emails.isEmpty())
            return out;

        Set<String> emailSet = new Set<String>();
        for (String e : emails) {
            if (String.isNotBlank(e))
                emailSet.add(e.toLowerCase());
        }
        if (emailSet.isEmpty())
            return out;

        Map<String, Map<String, String>> match = new Map<String, Map<String, String>>();
        for (Lead l : [
            SELECT Id, Email
            FROM Lead
            WHERE Email IN :emailSet
            WITH SECURITY_ENFORCED
            LIMIT 200
        ]) {
            if (l.Email == null)
                continue;
            String key = l.Email.toLowerCase();
            if (!match.containsKey(key)) {
                match.put(
                    key,
                    new Map<String, String>{ 'id' => l.Id, 'type' => 'Lead' }
                );
            }
        }
        // A person account's hidden contact shares its email; link to the Account instead.
        // IsPersonAccount only exists when Person Accounts is enabled, so the query is dynamic.
        Boolean personAccounts = ExtolePersonAccounts.isEnabled();
        String contactSoql =
            'SELECT Id, Email' +
            (personAccounts ? ', IsPersonAccount, AccountId' : '') +
            ' FROM Contact WHERE Email IN :emailSet WITH SECURITY_ENFORCED LIMIT 200';
        for (SObject c : Database.query(contactSoql)) {
            String contactEmail = (String) c.get('Email');
            if (contactEmail == null)
                continue;
            Boolean isPerson =
                personAccounts && c.get('IsPersonAccount') == true;
            match.put(
                contactEmail.toLowerCase(),
                new Map<String, String>{
                    'id' => isPerson
                        ? (String) c.get('AccountId')
                        : (String) c.get('Id'),
                    'type' => isPerson ? 'Account' : 'Contact'
                }
            );
        }
        for (String k : match.keySet()) {
            ExtolePersonCard.SfdcLink link = new ExtolePersonCard.SfdcLink();
            link.email = k;
            link.recordId = match.get(k).get('id');
            link.objectType = match.get(k).get('type');
            out.add(link);
        }
        return out;
    }

    // ── Private API helpers ───────────────────────────────────────────────────

    // Finds the advocate. Accounts keyed on email match on the identity key. For any other
    // identity key (a member number, say) that lookup finds nobody, so fall back to searching
    // by the email on the profile.
    private static Map<String, Object> lookupPerson(
        ExtoleConfig config,
        ExtoleClient client,
        String email
    ) {
        String encoded = EncodingUtil.urlEncode(email, 'UTF-8');
        Map<String, Object> person = firstPerson(
            config,
            client,
            ExtoleConstants.PEOPLE_PATH +
                '?identity_key_value=' +
                encoded +
                '&limit=1'
        );
        if (person != null)
            return person;
        return firstPerson(
            config,
            client,
            '/v2/persons?email=' + encoded + '&limit=1'
        );
    }

    private static Map<String, Object> firstPerson(
        ExtoleConfig config,
        ExtoleClient client,
        String path
    ) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + path);
        req.setMethod('GET');
        if (!config.isNamedCredentialMode())
            req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);

        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
            return null;

        List<Object> persons = (List<Object>) JSON.deserializeUntyped(
            res.getBody()
        );
        if (persons == null || persons.isEmpty())
            return null;
        return (Map<String, Object>) persons[0];
    }

    private static String otherIdentity(Map<String, Object> rel, String key) {
        Object other = rel.get('other_person');
        if (!(other instanceof Map<String, Object>))
            return null;
        return getString((Map<String, Object>) other, key);
    }

    private static String valueAt(List<String> values, Integer i) {
        return (values != null && i < values.size()) ? values[i] : null;
    }

    // The Extole client this connection belongs to, read from the token the
    // app calls with. Blank when it can't be found; the link still works then
    // for anyone who only has one client.
    private static String fetchClientId(
        ExtoleConfig config,
        ExtoleClient client
    ) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(config.getEndpoint() + ExtoleConstants.TOKENS_PATH);
            req.setMethod('GET');
            if (!config.isNamedCredentialMode())
                req.setHeader('Authorization', config.getAuthHeader());
            req.setTimeout(config.timeoutMs);
            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
                return null;
            Object parsed = JSON.deserializeUntyped(res.getBody());
            if (parsed instanceof List<Object>) {
                List<Object> items = (List<Object>) parsed;
                if (
                    items.isEmpty() ||
                    !(items[0] instanceof Map<String, Object>)
                )
                    return null;
                parsed = items[0];
            }
            if (!(parsed instanceof Map<String, Object>))
                return null;
            String clientId = getString(
                (Map<String, Object>) parsed,
                'client_id'
            );
            return String.isBlank(clientId) ? null : clientId;
        } catch (Exception e) {
            return null;
        }
    }

    // Opens the person's profile in My Extole. The client id makes My Extole
    // offer to switch client for people who can see more than one.
    @TestVisible
    private static String profileUrl(String personId, String clientId) {
        if (String.isBlank(personId))
            return null;
        String url =
            PROFILE_URL_BASE + EncodingUtil.urlEncode(personId, 'UTF-8');
        if (String.isNotBlank(clientId))
            url += '?client_id=' + EncodingUtil.urlEncode(clientId, 'UTF-8');
        return url;
    }

    private static List<ExtolePersonCard.ShareLink> fetchShareLinks(
        ExtoleConfig config,
        ExtoleClient client,
        String personId
    ) {
        List<ExtolePersonCard.ShareLink> out = new List<ExtolePersonCard.ShareLink>();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            config.getEndpoint() +
                ExtoleConstants.PEOPLE_PATH +
                '/' +
                personId +
                '/shareables'
        );
        req.setMethod('GET');
        if (!config.isNamedCredentialMode())
            req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);

        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
            return out;

        List<Object> raw = (List<Object>) JSON.deserializeUntyped(
            res.getBody()
        );
        if (raw == null)
            return out;
        for (Object o : raw) {
            Map<String, Object> m = (Map<String, Object>) o;
            ExtolePersonCard.ShareLink sl = new ExtolePersonCard.ShareLink();
            sl.code = getString(m, 'code');
            sl.link = getString(m, 'link');
            sl.program = getString(m, 'label');
            out.add(sl);
        }
        return out;
    }

    // Pages through every relationship. For email-keyed accounts exclude_anonymous drops people
    // who only clicked a share link and never identified themselves, so the list is sign-ups and
    // identified friends only.
    private static List<Map<String, Object>> fetchRelationships(
        ExtoleConfig config,
        ExtoleClient client,
        String personId,
        Boolean excludeAnonymous
    ) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Integer page = 0; page < MAX_PAGES; page++) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(
                config.getEndpoint() +
                    ExtoleConstants.PEOPLE_PATH +
                    '/' +
                    personId +
                    '/relationships?' +
                    (excludeAnonymous ? 'exclude_anonymous=true&' : '') +
                    'limit=' +
                    PAGE_SIZE +
                    '&offset=' +
                    (page * PAGE_SIZE)
            );
            req.setMethod('GET');
            if (!config.isNamedCredentialMode())
                req.setHeader('Authorization', config.getAuthHeader());
            req.setTimeout(config.timeoutMs);

            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
                break;

            List<Object> raw = (List<Object>) JSON.deserializeUntyped(
                res.getBody()
            );
            if (raw == null)
                break;
            for (Object o : raw) {
                out.add((Map<String, Object>) o);
            }
            if (raw.size() < PAGE_SIZE)
                break;
        }
        return out;
    }

    private static Map<String, ExtolePersonCard.Reward> fetchRewards(
        ExtoleConfig config,
        ExtoleClient client,
        String personId,
        Set<String> declinedFriendIds,
        Map<String, ExtolePersonCard.Reward> ownRewardByProgram,
        Map<String, Boolean> ownDeclinedByProgram
    ) {
        Map<String, ExtolePersonCard.Reward> out = new Map<String, ExtolePersonCard.Reward>();
        for (Integer page = 0; page < MAX_PAGES; page++) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(
                config.getEndpoint() +
                    ExtoleConstants.PEOPLE_PATH +
                    '/' +
                    personId +
                    '/rewards?limit=' +
                    PAGE_SIZE +
                    '&offset=' +
                    (page * PAGE_SIZE)
            );
            req.setMethod('GET');
            if (!config.isNamedCredentialMode())
                req.setHeader('Authorization', config.getAuthHeader());
            req.setTimeout(config.timeoutMs);

            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
                break;

            List<Object> raw = (List<Object>) JSON.deserializeUntyped(
                res.getBody()
            );
            if (raw == null)
                break;
            for (Object o : raw) {
                Map<String, Object> m = (Map<String, Object>) o;
                String state = getString(m, 'state');
                Boolean rewarded = REWARDED_STATES.contains(state);
                if (!rewarded && !DECLINED_STATES.contains(state))
                    continue;

                Object dataRaw = m.get('data');
                Map<String, Object> data = dataRaw instanceof Map<String, Object>
                    ? (Map<String, Object>) dataRaw
                    : new Map<String, Object>();
                String friendId = dataString(data, 'other_person_id');
                // A reward keyed on this person (or with no other person at all)
                // is this person's own, not one earned for referring someone.
                Object keyRaw = m.get('journey_key');
                String keyValue = keyRaw instanceof Map<String, Object>
                    ? getString((Map<String, Object>) keyRaw, 'value')
                    : null;
                Boolean isOwn = personId.equals(keyValue) || friendId == null;
                if (isOwn) {
                    String ownKey = programKey(m);
                    if (!rewarded) {
                        ownDeclinedByProgram.put(ownKey, true);
                    } else if (!ownRewardByProgram.containsKey(ownKey)) {
                        ExtolePersonCard.Reward own = buildReward(m, state);
                        if (friendId != null && !personId.equals(friendId))
                            own.referrerId = friendId;
                        ownRewardByProgram.put(ownKey, own);
                    }
                }
                if (friendId == null)
                    continue;
                if (!rewarded) {
                    declinedFriendIds.add(friendId);
                    continue;
                }
                if (out.containsKey(friendId))
                    continue;

                out.put(friendId, buildReward(m, state));
            }
            if (raw.size() < PAGE_SIZE)
                break;
        }
        return out;
    }

    // Real rewards and steps carry the program under 'program'. Blank means none.
    private static String programKey(Map<String, Object> m) {
        String p = getString(m, 'program');
        if (String.isBlank(p))
            p = getString(m, 'program_label');
        return String.isBlank(p) ? '' : p;
    }

    private static ExtolePersonCard.Reward buildReward(
        Map<String, Object> m,
        String state
    ) {
        ExtolePersonCard.Reward r = new ExtolePersonCard.Reward();
        r.rewardId = String.isNotBlank(getString(m, 'reward_id'))
            ? getString(m, 'reward_id')
            : getString(m, 'id');
        r.state = state;
        r.faceValueType = getString(m, 'face_value_type');
        r.dateEarned = String.isNotBlank(getString(m, 'earned_date'))
            ? getString(m, 'earned_date')
            : getString(m, 'date_earned');
        // Real rewards carry the program under 'program'.
        r.programLabel = String.isNotBlank(getString(m, 'program'))
            ? getString(m, 'program')
            : getString(m, 'program_label');
        r.campaignId = getString(m, 'campaign_id');
        Object fv = m.get('face_value');
        if (fv != null) {
            try {
                r.faceValue = Decimal.valueOf(String.valueOf(fv));
            } catch (Exception ignored) {
            }
        }
        if (r.faceValue != null)
            r.amountLabel = formatAmount(r.faceValue, r.faceValueType);
        return r;
    }

    private static String rewardStatus(
        ExtolePersonCard.Reward reward,
        Boolean declined
    ) {
        if (reward != null)
            return 'rewarded';
        return declined ? 'declined' : 'pending';
    }

    // Extole records each reward decision on the advocate's reward journey,
    // keyed by the friend. The latest decision for a friend wins, so a
    // re-evaluation or a manual approval can undo an earlier decline.
    private static void addDeclinedEvaluations(
        ExtoleConfig config,
        ExtoleClient client,
        String personId,
        Set<String> declinedFriendIds,
        Map<String, Boolean> ownDeclinedByProgram
    ) {
        Map<String, String> latestDate = new Map<String, String>();
        Map<String, Boolean> latestDeclined = new Map<String, Boolean>();
        // This person's own decisions are kept per program.
        Map<String, String> ownLatestDate = new Map<String, String>();
        Map<String, Boolean> ownLatestDeclined = new Map<String, Boolean>();
        try {
            for (Integer page = 0; page < MAX_DECISION_PAGES; page++) {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(
                    config.getEndpoint() +
                        ExtoleConstants.PEOPLE_PATH +
                        '/' +
                        personId +
                        '/steps?journey_names=reward&limit=' +
                        PAGE_SIZE +
                        '&offset=' +
                        (page * PAGE_SIZE)
                );
                req.setMethod('GET');
                if (!config.isNamedCredentialMode())
                    req.setHeader('Authorization', config.getAuthHeader());
                req.setTimeout(config.timeoutMs);

                HttpResponse res = client.send(config, req);
                if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
                    break;
                List<Object> raw = (List<Object>) JSON.deserializeUntyped(
                    res.getBody()
                );
                if (raw == null)
                    break;
                for (Object o : raw) {
                    Map<String, Object> step = (Map<String, Object>) o;
                    String name = getString(step, 'name');
                    Boolean declined;
                    if (name == 'reward_manually_declined')
                        declined = true;
                    else if (name == 'reward_manually_approved')
                        declined = false;
                    else if (name == 'reward_evaluated')
                        declined = 'declined'
                            .equals(decisionState(step.get('data')));
                    else
                        continue;

                    Object key = step.get('journey_key');
                    if (!(key instanceof Map<String, Object>))
                        continue;
                    String friendId = getString(
                        (Map<String, Object>) key,
                        'value'
                    );
                    String stepDate = getString(step, 'event_date');
                    if (friendId == null || stepDate == null)
                        continue;
                    if (friendId == personId) {
                        String ownKey = programKey(step);
                        if (
                            !ownLatestDate.containsKey(ownKey) ||
                            stepDate > ownLatestDate.get(ownKey)
                        ) {
                            ownLatestDate.put(ownKey, stepDate);
                            ownLatestDeclined.put(ownKey, declined);
                        }
                        continue;
                    }
                    if (
                        !latestDate.containsKey(friendId) ||
                        stepDate > latestDate.get(friendId)
                    ) {
                        latestDate.put(friendId, stepDate);
                        latestDeclined.put(friendId, declined);
                    }
                }
                if (raw.size() < PAGE_SIZE)
                    break;
            }
        } catch (Exception e) {
            // Without decisions every friend without a reward shows as pending.
            System.debug('addDeclinedEvaluations ERROR: ' + e.getMessage());
        }
        for (String friendId : latestDeclined.keySet()) {
            if (latestDeclined.get(friendId))
                declinedFriendIds.add(friendId);
        }
        for (String ownKey : ownLatestDeclined.keySet()) {
            ownDeclinedByProgram.put(ownKey, ownLatestDeclined.get(ownKey));
        }
    }

    // Says which referrer each program's reward belongs to. An issued reward
    // names the referrer itself; otherwise a program's reward journey does, as
    // long as only one of the person's referrers has one.
    private static void attributeRewardsToReferrers(
        ExtoleConfig config,
        ExtoleClient client,
        String personId,
        List<ExtolePersonCard.OwnProgram> programs,
        List<ExtolePersonCard.ReferredBy> referrers
    ) {
        Map<String, Set<String>> journeyReferrers = new Map<String, Set<String>>();
        Boolean needJourneys = false;
        for (ExtolePersonCard.OwnProgram op : programs) {
            if (op.reward != null && op.reward.referrerId != null) {
                op.rewardReferrerId = op.reward.referrerId;
            } else {
                needJourneys = true;
            }
        }
        if (needJourneys && Limits.getCallouts() < Limits.getLimitCallouts()) {
            try {
                journeyReferrers = fetchRewardJourneyReferrers(
                    config,
                    client,
                    personId
                );
            } catch (Exception e) {
                System.debug('attributeRewards ERROR: ' + e.getMessage());
            }
        }
        for (ExtolePersonCard.OwnProgram op : programs) {
            if (op.rewardReferrerId != null)
                continue;
            Set<String> ids = journeyReferrers.get(
                op.program == null ? '' : op.program
            );
            if (ids == null || ids.size() != 1)
                continue;
            for (String id : ids) {
                op.rewardReferrerId = id;
            }
        }
    }

    // The referrers this person has reward journeys with, per program. A
    // journey is with a referrer when the other person is its advocate.
    private static Map<String, Set<String>> fetchRewardJourneyReferrers(
        ExtoleConfig config,
        ExtoleClient client,
        String personId
    ) {
        Map<String, Set<String>> out = new Map<String, Set<String>>();
        HttpResponse res = client.send(
            config,
            getRequest(
                config,
                ExtoleConstants.PEOPLE_PATH +
                    '/' +
                    personId +
                    '/journeys?names=reward&limit=' +
                    PAGE_SIZE
            )
        );
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
            return out;
        Object parsed = JSON.deserializeUntyped(res.getBody());
        if (!(parsed instanceof List<Object>))
            return out;
        for (Object o : (List<Object>) parsed) {
            Map<String, Object> j = (Map<String, Object>) o;
            Object dataRaw = j.get('data');
            if (!(dataRaw instanceof Map<String, Object>))
                continue;
            Map<String, Object> data = (Map<String, Object>) dataRaw;
            if ('ADVOCATE' != dataString(data, 'other_person_role'))
                continue;
            String otherId = dataString(data, 'other_person_id');
            if (otherId == null)
                continue;
            String key = programKey(j);
            if (!out.containsKey(key))
                out.put(key, new Set<String>());
            out.get(key).add(otherId);
        }
        return out;
    }

    // Step data values arrive as {scope, value}.
    private static String decisionState(Object dataRaw) {
        if (!(dataRaw instanceof Map<String, Object>))
            return null;
        Object stateRaw = ((Map<String, Object>) dataRaw).get('state');
        if (stateRaw instanceof Map<String, Object>)
            stateRaw = ((Map<String, Object>) stateRaw).get('value');
        return stateRaw instanceof String
            ? ((String) stateRaw).toLowerCase()
            : null;
    }

    private class PersonProfile {
        String email;
        String displayName;
        List<ExtolePersonCard.JourneyStep> steps;
        PersonProfile(
            String e,
            String d,
            List<ExtolePersonCard.JourneyStep> s
        ) {
            email = e;
            displayName = d;
            steps = s;
        }
    }

    private static Map<String, PersonProfile> loadProfiles(
        ExtoleConfig config,
        ExtoleClient client,
        List<String> personIds,
        Map<String, String> personIdToProgram,
        Map<String, String> identityKeyById,
        Map<String, String> identityValueById,
        Set<String> friendPrograms,
        Set<String> attempted
    ) {
        Map<String, List<ExtolePersonCard.JourneyStep>> templateByProgram = fetchProgramTemplates(
            config,
            client,
            friendPrograms
        );
        return fetchPersonProfiles(
            config,
            client,
            personIds,
            personIdToProgram,
            identityKeyById,
            identityValueById,
            templateByProgram,
            attempted
        );
    }

    private static void applyProfile(
        ExtolePersonCard.Friend f,
        PersonProfile profile
    ) {
        if (profile == null)
            return;
        f.email = profile.email;
        f.displayName = String.isNotBlank(profile.displayName)
            ? profile.displayName
            : profile.email;
        f.steps = profile.steps;
    }

    private static Map<String, PersonProfile> fetchPersonProfiles(
        ExtoleConfig config,
        ExtoleClient client,
        List<String> personIds,
        Map<String, String> personIdToProgram,
        Map<String, String> identityKeyById,
        Map<String, String> identityValueById,
        Map<String, List<ExtolePersonCard.JourneyStep>> templateByProgram,
        Set<String> attempted
    ) {
        Map<String, PersonProfile> out = new Map<String, PersonProfile>();
        for (String pid : personIds) {
            // The relationship row already carries the friend's identity key and value, which
            // saves the profile callout. Without it the profile is fetched as before.
            Boolean identified =
                String.isNotBlank(identityValueById.get(pid)) &&
                String.isNotBlank(identityKeyById.get(pid));
            Integer needed = identified
                ? CALLOUTS_PER_FRIEND_IDENTIFIED
                : CALLOUTS_PER_FRIEND;
            // Stop before the transaction runs out of callouts or time; callers continue from here.
            if (
                Limits.getCallouts() + needed > Limits.getLimitCallouts() ||
                System.currentTimeMillis() - START_MS > MAX_ELAPSED_MS
            ) {
                break;
            }
            attempted.add(pid);
            try {
                ExtolePerson p;
                if (identified) {
                    p = ExtolePerson.fromMap(
                        new Map<String, Object>{
                            'id' => pid,
                            'identity_key' => identityKeyById.get(pid),
                            'identity_key_value' => identityValueById.get(pid)
                        }
                    );
                } else {
                    HttpResponse res = client.send(
                        config,
                        ExtoleGetPersonRequest.byId(pid).build(config)
                    );
                    if (
                        res.getStatusCode() < 200 ||
                        res.getStatusCode() >= 300
                    ) {
                        System.debug(
                            'fetchPersonProfiles ' +
                                pid +
                                ' status=' +
                                res.getStatusCode()
                        );
                        continue;
                    }
                    p = ExtolePerson.fromMap(
                        (Map<String, Object>) JSON.deserializeUntyped(
                            res.getBody()
                        )
                    );
                }
                // applyData replaces the email with the profile's email attribute, which some
                // accounts never set. Keep the identity email when that attribute is empty.
                String identityEmail = p.email;

                HttpRequest dataReq = new HttpRequest();
                dataReq.setEndpoint(
                    config.getEndpoint() +
                        ExtoleConstants.PEOPLE_PATH +
                        '/' +
                        pid +
                        '/data'
                );
                dataReq.setMethod('GET');
                if (!config.isNamedCredentialMode())
                    dataReq.setHeader('Authorization', config.getAuthHeader());
                dataReq.setTimeout(config.timeoutMs);
                HttpResponse dataRes = client.send(config, dataReq);
                if (
                    dataRes.getStatusCode() >= 200 &&
                    dataRes.getStatusCode() < 300
                ) {
                    p.applyData(
                        (Map<String, Object>) JSON.deserializeUntyped(
                            dataRes.getBody()
                        )
                    );
                }
                if (String.isBlank(p.email))
                    p.email = identityEmail;

                List<ExtolePersonCard.JourneyStep> completedSteps = fetchFriendStepsData(
                    config,
                    client,
                    pid,
                    null,
                    false
                );
                List<ExtolePersonCard.JourneyStep> steps = completedSteps;
                String prog = personIdToProgram.get(pid);
                if (
                    prog != null &&
                    templateByProgram.containsKey(prog) &&
                    !templateByProgram.get(prog).isEmpty()
                ) {
                    steps = mergeSteps(
                        templateByProgram.get(prog),
                        completedSteps
                    );
                }
                out.put(
                    pid,
                    new PersonProfile(p.email, buildDisplayName(p), steps)
                );
            } catch (Exception e) {
                System.debug(
                    'fetchPersonProfiles ERROR for ' +
                        pid +
                        ': ' +
                        e.getMessage()
                );
            }
        }
        return out;
    }

    private static Map<String, List<ExtolePersonCard.JourneyStep>> fetchProgramTemplates(
        ExtoleConfig config,
        ExtoleClient client,
        Set<String> programs
    ) {
        Map<String, List<ExtolePersonCard.JourneyStep>> out = new Map<String, List<ExtolePersonCard.JourneyStep>>();
        if (programs.isEmpty())
            return out;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            config.getEndpoint() + ExtoleConstants.CAMPAIGNS_SUMMARY_PATH
        );
        req.setMethod('GET');
        if (!config.isNamedCredentialMode())
            req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);

        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
            return out;

        List<Object> raw = (List<Object>) JSON.deserializeUntyped(
            res.getBody()
        );
        if (raw == null)
            return out;

        // Build program → campaignId, preferring LIVE state
        Map<String, String> programToCampaignId = new Map<String, String>();
        for (Object o : raw) {
            Map<String, Object> c = (Map<String, Object>) o;
            String prog = getString(c, 'program_label');
            if (!programs.contains(prog))
                continue;
            String cid = getString(c, 'campaign_id');
            if (cid == null)
                continue;
            if (
                !programToCampaignId.containsKey(prog) ||
                'LIVE'.equals(getString(c, 'state'))
            ) {
                programToCampaignId.put(prog, cid);
            }
        }

        for (String prog : programToCampaignId.keySet()) {
            String cid = programToCampaignId.get(prog);
            Set<String> friendControllerNames = fetchFriendControllerStepNames(
                config,
                client,
                cid
            );
            out.put(
                prog,
                fetchCampaignFlowSteps(
                    config,
                    client,
                    cid,
                    friendControllerNames
                )
            );
        }
        return out;
    }

    // Extole system steps — referral attribution and click-tracking infrastructure, never user-facing milestones.
    private static final Set<String> ATTRIBUTION_STEPS = new Set<String>{
        'was_referred',
        'friend_confirmed',
        'friend_click',
        'share_click',
        'share_clicked',
        'share_destination_rendered'
    };

    private static List<ExtolePersonCard.JourneyStep> fetchFriendStepsData(
        ExtoleConfig config,
        ExtoleClient client,
        String pid,
        String ownProgram,
        Boolean isOwn
    ) {
        List<ExtolePersonCard.JourneyStep> out = new List<ExtolePersonCard.JourneyStep>();
        HttpRequest req = new HttpRequest();
        // A friend under an advocate is always in the FRIEND journey. A person's
        // own steps can be a friend's or a participant's, and belong to one
        // program, so one offer's steps don't mix with another's.
        String journeys = isOwn
            ? 'journey_names=FRIEND&journey_names=PARTICIPANT'
            : 'journey_names=FRIEND';
        String programFilter = isOwn && String.isNotBlank(ownProgram)
            ? '&programs=' + EncodingUtil.urlEncode(ownProgram, 'UTF-8')
            : '';
        req.setEndpoint(
            config.getEndpoint() +
                ExtoleConstants.PEOPLE_PATH +
                '/' +
                pid +
                '/steps?limit=25&' +
                journeys +
                '&is_primary=true' +
                programFilter
        );
        req.setMethod('GET');
        if (!config.isNamedCredentialMode())
            req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);
        try {
            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
                return out;
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(
                res.getBody()
            );
            if (raw == null)
                return out;
            for (Object o : raw) {
                Map<String, Object> s = (Map<String, Object>) o;
                String name = getString(s, 'name');
                if (name == null || ATTRIBUTION_STEPS.contains(name))
                    continue;
                ExtolePersonCard.JourneyStep step = new ExtolePersonCard.JourneyStep();
                step.name = name;
                String apiLabel = getString(s, 'label');
                step.label = String.isNotBlank(apiLabel)
                    ? apiLabel
                    : prettifyStepName(name);
                step.dateCompleted = getString(s, 'event_date');
                step.failed = 'LOW'.equals(getString(s, 'quality'));
                out.add(step);
            }
        } catch (Exception e) {
            System.debug(
                'fetchFriendStepsData ERROR for ' + pid + ': ' + e.getMessage()
            );
        }
        return out;
    }

    private static Set<String> fetchFriendControllerStepNames(
        ExtoleConfig config,
        ExtoleClient client,
        String campaignId
    ) {
        Set<String> names = new Set<String>();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            config.getEndpoint() +
                ExtoleConstants.CAMPAIGNS_PATH +
                '/' +
                campaignId +
                '/controllers/built'
        );
        req.setMethod('GET');
        if (!config.isNamedCredentialMode())
            req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);
        try {
            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
                return names;
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(
                res.getBody()
            );
            if (raw == null)
                return names;
            for (Object o : raw) {
                Map<String, Object> c = (Map<String, Object>) o;
                Object jnRaw = c.get('journey_names');
                if (!(jnRaw instanceof List<Object>))
                    continue;
                for (Object jn : (List<Object>) jnRaw) {
                    // A referred friend's events are in the FRIEND journey; an
                    // offer participant's are in the PARTICIPANT journey.
                    String journey = String.valueOf(jn);
                    if (
                        'FRIEND'.equals(journey) ||
                        'PARTICIPANT'.equals(journey)
                    ) {
                        String cname = getString(c, 'name');
                        if (cname != null)
                            names.add(cname);
                        break;
                    }
                }
            }
        } catch (Exception e) {
            System.debug(
                'fetchFriendControllerStepNames ERROR campaign=' +
                    campaignId +
                    ': ' +
                    e.getMessage()
            );
        }
        return names;
    }

    private static List<ExtolePersonCard.JourneyStep> fetchCampaignFlowSteps(
        ExtoleConfig config,
        ExtoleClient client,
        String campaignId,
        Set<String> friendStepNames
    ) {
        List<ExtolePersonCard.JourneyStep> out = new List<ExtolePersonCard.JourneyStep>();
        if (friendStepNames.isEmpty())
            return out;
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            config.getEndpoint() +
                ExtoleConstants.CAMPAIGNS_PATH +
                '/' +
                campaignId +
                '/flow-steps/built'
        );
        req.setMethod('GET');
        if (!config.isNamedCredentialMode())
            req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);
        try {
            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
                return out;
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(
                res.getBody()
            );
            if (raw == null)
                return out;
            List<Map<String, Object>> filtered = new List<Map<String, Object>>();
            for (Object o : raw) {
                Map<String, Object> fs = (Map<String, Object>) o;
                if (!'/business-events'.equals(getString(fs, 'flow_path')))
                    continue;
                String stepName = getString(fs, 'step_name');
                if (stepName == null || ATTRIBUTION_STEPS.contains(stepName))
                    continue;
                if (!friendStepNames.contains(stepName))
                    continue;
                filtered.add(fs);
            }
            // sort by sequence (bubble sort)
            for (Integer i = 0; i < filtered.size() - 1; i++) {
                for (Integer j = 0; j < filtered.size() - 1 - i; j++) {
                    if (
                        getInteger(filtered[j], 'sequence') >
                        getInteger(filtered[j + 1], 'sequence')
                    ) {
                        Map<String, Object> tmp = filtered[j];
                        filtered[j] = filtered[j + 1];
                        filtered[j + 1] = tmp;
                    }
                }
            }
            for (Map<String, Object> fs : filtered) {
                ExtolePersonCard.JourneyStep step = new ExtolePersonCard.JourneyStep();
                step.name = getString(fs, 'step_name');
                String apiLabel = getString(fs, 'name');
                step.label = String.isNotBlank(apiLabel)
                    ? apiLabel
                    : prettifyStepName(step.name);
                out.add(step);
            }
        } catch (Exception e) {
            System.debug(
                'fetchCampaignFlowSteps ERROR campaign=' +
                    campaignId +
                    ': ' +
                    e.getMessage()
            );
        }
        return out;
    }

    private static List<ExtolePersonCard.JourneyStep> mergeSteps(
        List<ExtolePersonCard.JourneyStep> flowSteps,
        List<ExtolePersonCard.JourneyStep> completed
    ) {
        Map<String, String> dateByName = new Map<String, String>();
        // A step counts as failed only when every occurrence failed quality.
        Map<String, Boolean> failedByName = new Map<String, Boolean>();
        for (ExtolePersonCard.JourneyStep s : completed) {
            if (s.name != null && s.dateCompleted != null) {
                dateByName.put(s.name, s.dateCompleted);
                Boolean prior = failedByName.get(s.name);
                failedByName.put(
                    s.name,
                    (prior == null || prior) && s.failed == true
                );
            }
        }
        List<ExtolePersonCard.JourneyStep> result = new List<ExtolePersonCard.JourneyStep>();
        for (ExtolePersonCard.JourneyStep template : flowSteps) {
            ExtolePersonCard.JourneyStep step = new ExtolePersonCard.JourneyStep();
            step.name = template.name;
            step.label = template.label;
            step.dateCompleted = dateByName.get(template.name);
            step.failed = failedByName.get(template.name) == true;
            result.add(step);
        }
        return result;
    }

    private static Integer getInteger(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v instanceof Integer)
            return (Integer) v;
        if (v instanceof Decimal)
            return ((Decimal) v).intValue();
        return 0;
    }

    private static String prettifyStepName(String name) {
        if (String.isBlank(name))
            return name;
        String result = '';
        for (String part : name.split('_')) {
            if (String.isNotBlank(part)) {
                result +=
                    (result.length() > 0 ? ' ' : '') +
                    part.substring(0, 1).toUpperCase() +
                    part.substring(1).toLowerCase();
            }
        }
        return result;
    }

    private static String buildDisplayName(ExtolePerson p) {
        String name = '';
        if (String.isNotBlank(p.firstName))
            name = p.firstName;
        if (String.isNotBlank(p.lastName))
            name = (name + ' ' + p.lastName).trim();
        return String.isNotBlank(name) ? name : p.email;
    }

    // ── Shared helpers ────────────────────────────────────────────────────────

    // One entry per program the person is in themselves: the programs that
    // referred them, plus any they earned or were declined a reward in. Each
    // carries that program's steps and reward.
    private static List<ExtolePersonCard.OwnProgram> buildOwnPrograms(
        ExtoleConfig config,
        ExtoleClient client,
        String personId,
        List<ExtolePersonCard.ReferredBy> referrers,
        Map<String, ExtolePersonCard.Reward> rewardByProgram,
        Map<String, Boolean> declinedByProgram,
        List<String> extraPrograms
    ) {
        List<ExtolePersonCard.OwnProgram> out = new List<ExtolePersonCard.OwnProgram>();
        List<String> programs = new List<String>();
        Set<String> seen = new Set<String>();
        for (ExtolePersonCard.ReferredBy rb : referrers) {
            String key = String.isBlank(rb.program) ? '' : rb.program;
            if (seen.add(key))
                programs.add(key);
        }
        for (String key : rewardByProgram.keySet()) {
            if (seen.add(key))
                programs.add(key);
        }
        for (String key : declinedByProgram.keySet()) {
            if (seen.add(key))
                programs.add(key);
        }
        for (String key : extraPrograms) {
            if (seen.add(key))
                programs.add(key);
        }
        if (programs.isEmpty())
            return out;

        Set<String> named = new Set<String>();
        for (String key : programs) {
            if (key != '' && named.size() < MAX_OWN_PROGRAMS)
                named.add(key);
        }
        Map<String, List<ExtolePersonCard.JourneyStep>> templates = new Map<String, List<ExtolePersonCard.JourneyStep>>();
        try {
            templates = fetchProgramTemplates(config, client, named);
        } catch (Exception e) {
            System.debug('buildOwnPrograms templates ERROR: ' + e.getMessage());
        }

        for (String key : programs) {
            if (out.size() >= MAX_OWN_PROGRAMS)
                break;
            ExtolePersonCard.OwnProgram op = new ExtolePersonCard.OwnProgram();
            op.program = key == '' ? null : key;
            op.reward = rewardByProgram.get(key);
            Boolean declined = declinedByProgram.get(key) == true;
            op.status = op.reward != null
                ? 'rewarded'
                : (declined ? 'declined' : 'pending');
            if (Limits.getCallouts() < Limits.getLimitCallouts()) {
                List<ExtolePersonCard.JourneyStep> completed = fetchFriendStepsData(
                    config,
                    client,
                    personId,
                    op.program,
                    true
                );
                List<ExtolePersonCard.JourneyStep> template = templates.get(
                    key
                );
                op.steps = template != null && !template.isEmpty()
                    ? mergeSteps(template, completed)
                    : completed;
            }
            out.add(op);
        }
        return out;
    }

    private static List<String> collectEmails(ExtolePersonCard.CardData data) {
        List<String> emails = new List<String>();
        if (data.friends != null) {
            for (ExtolePersonCard.Friend f : data.friends) {
                if (String.isNotBlank(f.email))
                    emails.add(f.email);
            }
        }
        for (ExtolePersonCard.ReferredBy rb : data.referrers) {
            if (String.isNotBlank(rb.email))
                emails.add(rb.email);
        }
        return emails;
    }

    private static void applySfdcLinks(
        ExtolePersonCard.CardData data,
        List<ExtolePersonCard.SfdcLink> links
    ) {
        if (links == null || links.isEmpty())
            return;
        Map<String, ExtolePersonCard.SfdcLink> byEmail = new Map<String, ExtolePersonCard.SfdcLink>();
        for (ExtolePersonCard.SfdcLink l : links) {
            if (l.email != null)
                byEmail.put(l.email.toLowerCase(), l);
        }
        if (data.friends != null) {
            for (ExtolePersonCard.Friend f : data.friends) {
                if (f.email == null)
                    continue;
                ExtolePersonCard.SfdcLink l = byEmail.get(
                    f.email.toLowerCase()
                );
                if (l != null) {
                    f.sfdcRecordId = l.recordId;
                    f.sfdcObjectType = l.objectType;
                }
            }
        }
        for (ExtolePersonCard.ReferredBy rb : data.referrers) {
            if (rb.email == null)
                continue;
            ExtolePersonCard.SfdcLink l = byEmail.get(rb.email.toLowerCase());
            if (l != null) {
                rb.sfdcRecordId = l.recordId;
                rb.sfdcObjectType = l.objectType;
            }
        }
    }

    // Reward data entries arrive as plain values or as {name, value} objects.
    private static String dataString(Map<String, Object> data, String key) {
        Object v = data.get(key);
        if (v instanceof Map<String, Object>)
            v = ((Map<String, Object>) v).get('value');
        return v instanceof String ? (String) v : null;
    }

    private static String getString(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v instanceof String ? (String) v : null;
    }
}
