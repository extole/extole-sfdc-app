/**
 * ExtolePersonCardController
 *
 * Drives the per-person LWC on Lead and Contact record pages. Composes a
 * single payload from multiple Extole endpoints + SFDC cross-record lookup:
 *
 *   1. Resolve email → person ID                 (ExtoleGetPersonRequest.byEmail)
 *   2. /v5/persons/{id}/shareables               share links
 *   3. /v5/persons/{id}/relationships            outgoing friends + incoming referrer
 *   4. /v5/persons/{id}/rewards                  rewards (state machine source of truth)
 *   5. For each friend (capped):                 resolve friend identity for display
 *   6. SOQL Lead + Contact by email              cross-link friends back to SFDC records
 *
 * Card self-hides when hasAnyData is false — no empty-state card on records
 * with no Extole activity.
 */
public with sharing class ExtolePersonCardController {

    private static final Integer MAX_FRIENDS = 10;

    @AuraEnabled(cacheable=true)
    public static ExtolePersonCard getCardForEmail(String email) {
        ExtolePersonCard card = new ExtolePersonCard();
        card.email = email;
        if (String.isBlank(email)) return card;

        try {
            ExtoleConfig config = new ExtoleConfig('Extole_API');
            ExtoleClient client = new ExtoleClient();

            // 1. Resolve identity
            ExtolePerson advocate = resolvePerson(client, config, email);
            if (advocate == null) {
                return card; // hasAnyData stays false → card self-hides
            }
            card.personId    = advocate.id;
            card.displayName = composeDisplayName(advocate);

            // 2-4. Fan-out: shareables, relationships, rewards
            List<ExtolePersonCard.ShareLink> shareLinks   = fetchShareLinks(client, config, advocate.id);
            Map<String, Object> relSplit                  = fetchRelationships(client, config, advocate.id);
            Map<String, List<Map<String, Object>>> outgoingByFriend =
                (Map<String, List<Map<String, Object>>>) relSplit.get('outgoingByFriend');
            List<Map<String, Object>> incomingRaw         = (List<Map<String, Object>>) relSplit.get('incoming');
            List<ExtolePersonCard.RewardSummary> rewards  = fetchRewards(client, config, advocate.id);

            card.shareLinks = shareLinks;
            card.rewards    = rewards;

            // Collect unique campaign IDs across all engagements to fetch each
            // campaign's business-event allowlist once.
            Set<String> campaignIds = new Set<String>();
            for (List<Map<String, Object>> rels : outgoingByFriend.values()) {
                for (Map<String, Object> rel : rels) {
                    String cid = (String) rel.get('campaign_id');
                    if (String.isNotBlank(cid)) campaignIds.add(cid);
                }
            }
            Map<String, Map<String, String>> milestonesByCampaign =
                fetchMilestoneAllowlists(client, config, campaignIds);

            // Build one Friend per unique identity, with all their engagements.
            // Cap at MAX_FRIENDS to keep request volume bounded.
            List<ExtolePersonCard.Friend> friends = new List<ExtolePersonCard.Friend>();
            Integer count = 0;
            for (String friendId : outgoingByFriend.keySet()) {
                if (count >= MAX_FRIENDS) break;
                friends.add(buildFriendWithEngagements(
                    client, config, friendId, outgoingByFriend.get(friendId),
                    rewards, milestonesByCampaign));
                count++;
            }
            card.friends = friends;

            // Incoming: this person was referred by someone (Lead-friendly mode)
            if (incomingRaw != null && !incomingRaw.isEmpty()) {
                card.referredBy = buildIncomingReferral(client, config, incomingRaw[0]);
            }

            // 6. SFDC cross-record lookup
            attachSfdcRecordIds(card);

            // Aggregate totals + flag for self-hide
            card.totalEarnedLabel = summarizeRewards(rewards);
            card.hasAnyData = !shareLinks.isEmpty()
                || !friends.isEmpty()
                || !rewards.isEmpty()
                || card.referredBy != null;
        } catch (Exception e) {
            // Non-fatal — card returns with hasAnyData=false so it just hides.
            // Log for diagnostics.
            System.debug('ExtolePersonCardController.getCardForEmail ERROR: ' + e.getMessage());
        }
        return card;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ──────────────────────────────────────────────────────────────────────

    private static ExtolePerson resolvePerson(ExtoleClient client, ExtoleConfig config, String email) {
        HttpRequest req = ExtoleGetPersonRequest.byEmail(email).build(config);
        HttpResponse res = client.send(config, req);
        ExtoleGetPersonResponse resp = ExtoleGetPersonResponse.fromResponse(res);
        if (resp.person == null || String.isBlank(resp.person.id)) return null;

        // Fetch /data for first_name/last_name
        HttpRequest dataReq = simpleGet(config, ExtoleConstants.PEOPLE_PATH + '/' + resp.person.id + '/data');
        try {
            HttpResponse dataRes = client.send(config, dataReq);
            if (dataRes.getStatusCode() >= 200 && dataRes.getStatusCode() < 300) {
                Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(dataRes.getBody());
                resp.person.applyData(dataMap);
            }
        } catch (Exception ignored) { }
        return resp.person;
    }

    private static List<ExtolePersonCard.ShareLink> fetchShareLinks(
            ExtoleClient client, ExtoleConfig config, String personId) {
        List<ExtolePersonCard.ShareLink> out = new List<ExtolePersonCard.ShareLink>();
        HttpRequest req = simpleGet(config, ExtoleConstants.PEOPLE_PATH + '/' + personId + '/shareables');
        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return out;
        List<Object> items = (List<Object>) JSON.deserializeUntyped(res.getBody());
        for (Object o : items) {
            Map<String, Object> m = (Map<String, Object>) o;
            ExtolePersonCard.ShareLink sl = new ExtolePersonCard.ShareLink();
            // Some accounts return `key` populated; others use `label`. Prefer
            // whichever is non-empty so the program tag always renders.
            String key = (String) m.get('key');
            String label = (String) m.get('label');
            sl.program     = String.isNotBlank(key) ? key : label;
            sl.code        = (String) m.get('code');
            sl.link        = (String) m.get('link');
            sl.createdDate = (String) m.get('created_date');
            out.add(sl);
        }
        return out;
    }

    /**
     * Returns { 'outgoingByFriend': Map<friendId, List<rel>>, 'incoming': List<rel> }.
     *
     * Outgoing relationships are grouped by friend identity — one friend can
     * have multiple relationship records (one per campaign they've engaged
     * with), and we want to render that hierarchy faithfully: friend identity
     * on the outside, per-campaign engagement nested inside.
     *
     * Filters out non-production containers (bot, test) so the card stays clean.
     */
    private static Map<String, Object> fetchRelationships(
            ExtoleClient client, ExtoleConfig config, String personId) {
        Map<String, List<Map<String, Object>>> outgoingByFriend =
            new Map<String, List<Map<String, Object>>>();
        List<Map<String, Object>> incoming = new List<Map<String, Object>>();
        HttpRequest req = simpleGet(config, ExtoleConstants.PEOPLE_PATH + '/' + personId + '/relationships');
        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            List<Object> items = (List<Object>) JSON.deserializeUntyped(res.getBody());
            for (Object o : items) {
                Map<String, Object> m = (Map<String, Object>) o;
                if (!'production'.equals(m.get('container'))) continue;
                String role = (String) m.get('my_role');
                if ('ADVOCATE'.equalsIgnoreCase(role)) {
                    String friendId = (String) m.get('other_person_id');
                    if (String.isBlank(friendId)) continue;
                    if (!outgoingByFriend.containsKey(friendId)) {
                        outgoingByFriend.put(friendId, new List<Map<String, Object>>());
                    }
                    outgoingByFriend.get(friendId).add(m);
                } else if ('FRIEND'.equalsIgnoreCase(role)) {
                    incoming.add(m);
                }
            }
        }
        return new Map<String, Object>{
            'outgoingByFriend' => outgoingByFriend,
            'incoming'         => incoming
        };
    }

    private static List<ExtolePersonCard.RewardSummary> fetchRewards(
            ExtoleClient client, ExtoleConfig config, String personId) {
        List<ExtolePersonCard.RewardSummary> out = new List<ExtolePersonCard.RewardSummary>();
        HttpRequest req = simpleGet(config, ExtoleConstants.PEOPLE_PATH + '/' + personId + '/rewards?limit=50');
        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return out;
        List<Object> items = (List<Object>) JSON.deserializeUntyped(res.getBody());
        for (Object o : items) {
            Map<String, Object> m = (Map<String, Object>) o;
            ExtolePersonCard.RewardSummary r = new ExtolePersonCard.RewardSummary();
            r.state         = (String) m.get('state');
            r.program       = (String) m.get('program');
            r.earnedDate    = (String) m.get('created_date');
            r.causeEventId  = (String) m.get('cause_event_id');
            r.amountLabel   = formatRewardAmount(m);
            out.add(r);
        }
        return out;
    }

    /**
     * For each campaign ID, fetch the FRIEND-journey business-event milestones.
     * Returns Map<campaignId, Map<eventName, displayDescription>>.
     *
     * A campaign's business-event-v10.0 components declare which events count
     * as "official milestones" AND which journey they belong to (FRIEND,
     * ADVOCATE, EVERYONE, EMPLOYEE_MARKETING, etc.). For a friend's milestone
     * strip on the advocate card, we want ONLY FRIEND-journey events — events
     * like `member_invited` (EVERYONE) aren't part of the friend's actual
     * journey; they're shared markers that would clutter the display.
     *
     * Streaming parse to avoid the 6MB Apex heap blow-out — each campaign's
     * /v1/components response is 5MB+ of nested config text. We pluck only
     * the top-level `name`, `type`, `description` and walk into the `variables`
     * array to find the journeyName variable's default value.
     */
    private static Map<String, Map<String, String>> fetchMilestoneAllowlists(
            ExtoleClient client, ExtoleConfig config, Set<String> campaignIds) {
        Map<String, Map<String, String>> out = new Map<String, Map<String, String>>();
        for (String cid : campaignIds) {
            Map<String, String> milestones = new Map<String, String>();
            try {
                HttpRequest req = simpleGet(config, '/v1/components?campaign_id=' + cid + '&limit=500');
                HttpResponse res = client.send(config, req);
                if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                    milestones = parseFriendBusinessEvents(res.getBody());
                }
            } catch (Exception ignored) { }
            out.put(cid, milestones);
        }
        return out;
    }

    /**
     * Streaming parser. Returns Map<eventName, description> for components
     * where type=business-event-v10.0 AND variables[journeyName].default=FRIEND.
     */
    @TestVisible
    private static Map<String, String> parseFriendBusinessEvents(String body) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(body)) return out;
        JSONParser p = JSON.createParser(body);
        Integer depth = 0;
        String currentName = null;
        String currentType = null;
        String currentDescription = null;
        String currentJourney = null;
        while (p.nextToken() != null) {
            JSONToken t = p.getCurrentToken();
            if (t == JSONToken.START_OBJECT) {
                depth++;
                if (depth == 1) {
                    currentName = null;
                    currentType = null;
                    currentDescription = null;
                    currentJourney = null;
                }
            } else if (t == JSONToken.END_OBJECT) {
                if (depth == 1
                    && 'business-event-v10.0'.equals(currentType)
                    && 'FRIEND'.equals(currentJourney)
                    && String.isNotBlank(currentName)) {
                    out.put(currentName, currentDescription);
                }
                depth--;
            } else if (t == JSONToken.FIELD_NAME && depth == 1) {
                String field = p.getCurrentName();
                if ('name'.equals(field)) {
                    p.nextToken();
                    if (p.getCurrentToken() == JSONToken.VALUE_STRING) currentName = p.getText();
                } else if ('type'.equals(field)) {
                    p.nextToken();
                    if (p.getCurrentToken() == JSONToken.VALUE_STRING) currentType = p.getText();
                } else if ('description'.equals(field)) {
                    p.nextToken();
                    if (p.getCurrentToken() == JSONToken.VALUE_STRING) currentDescription = p.getText();
                } else if ('variables'.equals(field)) {
                    currentJourney = extractJourneyFromVariables(p);
                } else {
                    p.nextToken();
                    p.skipChildren();
                }
            }
        }
        return out;
    }

    /**
     * Called when parser is positioned at the FIELD_NAME "variables". Walks
     * into the variables array, finds the journeyName variable, returns its
     * values.default string. Leaves parser positioned at the END_ARRAY.
     */
    private static String extractJourneyFromVariables(JSONParser p) {
        String journey = null;
        p.nextToken(); // START_ARRAY
        if (p.getCurrentToken() != JSONToken.START_ARRAY) return null;
        while (p.nextToken() != JSONToken.END_ARRAY) {
            if (p.getCurrentToken() != JSONToken.START_OBJECT) continue;
            String varName = null;
            String varDefault = null;
            while (p.nextToken() != JSONToken.END_OBJECT) {
                if (p.getCurrentToken() != JSONToken.FIELD_NAME) continue;
                String vf = p.getCurrentName();
                if ('name'.equals(vf)) {
                    p.nextToken();
                    if (p.getCurrentToken() == JSONToken.VALUE_STRING) varName = p.getText();
                } else if ('values'.equals(vf)) {
                    p.nextToken();
                    if (p.getCurrentToken() == JSONToken.START_OBJECT) {
                        while (p.nextToken() != JSONToken.END_OBJECT) {
                            if (p.getCurrentToken() == JSONToken.FIELD_NAME && 'default'.equals(p.getCurrentName())) {
                                p.nextToken();
                                if (p.getCurrentToken() == JSONToken.VALUE_STRING) varDefault = p.getText();
                                else p.skipChildren();
                            } else {
                                p.nextToken();
                                p.skipChildren();
                            }
                        }
                    }
                } else {
                    p.nextToken();
                    p.skipChildren();
                }
            }
            if ('journeyName'.equals(varName) && String.isNotBlank(varDefault)) {
                journey = varDefault;
                // keep consuming the rest of the array so the parser ends positioned correctly
            }
        }
        return journey;
    }

    private static ExtolePersonCard.Friend buildFriendWithEngagements(
            ExtoleClient client, ExtoleConfig config, String friendId,
            List<Map<String, Object>> friendRels,
            List<ExtolePersonCard.RewardSummary> advocateRewards,
            Map<String, Map<String, String>> milestonesByCampaign) {
        ExtolePersonCard.Friend f = new ExtolePersonCard.Friend();
        f.friendPersonId = friendId;

        // Identity: fetched once per friend regardless of how many engagements.
        try {
            HttpRequest req = simpleGet(config, ExtoleConstants.PEOPLE_PATH + '/' + friendId);
            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                f.email = (String) m.get('identity_key_value');
                HttpRequest dataReq = simpleGet(config, ExtoleConstants.PEOPLE_PATH + '/' + friendId + '/data');
                HttpResponse dataRes = client.send(config, dataReq);
                if (dataRes.getStatusCode() >= 200 && dataRes.getStatusCode() < 300) {
                    Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(dataRes.getBody());
                    String first = nestedValue(dataMap, 'first_name');
                    String last  = nestedValue(dataMap, 'last_name');
                    if (String.isNotBlank(first) || String.isNotBlank(last)) {
                        f.displayName = ((first == null ? '' : first) + ' ' + (last == null ? '' : last)).trim();
                    }
                }
            }
        } catch (Exception ignored) { }
        if (String.isBlank(f.displayName)) f.displayName = f.email != null ? f.email : friendId;

        // Steps: fetched once per friend, filtered per-engagement by campaign.
        List<Map<String, Object>> allSteps = fetchAllSteps(client, config, friendId);

        // Build one engagement per relationship record, ordered by created_date.
        // Each engagement shows the friend's progress in that specific campaign.
        for (Map<String, Object> rel : friendRels) {
            ExtolePersonCard.CampaignEngagement eng = new ExtolePersonCard.CampaignEngagement();
            eng.program        = (String) rel.get('program');
            eng.campaignId     = (String) rel.get('campaign_id');
            eng.createdDate    = (String) rel.get('created_date');
            eng.shareableCode  = pullNamedValue(rel, 'shareable_code');

            Map<String, String> allowed = milestonesByCampaign.get(eng.campaignId);
            eng.milestones = filterStepsToMilestones(allSteps, eng.campaignId, allowed);

            // Reward attribution: match by cause_event_id (V2: chain-walk for transitive causes)
            String causeEventId = (String) rel.get('cause_event_id');
            for (ExtolePersonCard.RewardSummary r : advocateRewards) {
                if (r.causeEventId != null && causeEventId != null && r.causeEventId.equals(causeEventId)) {
                    eng.reward = r;
                    break;
                }
            }
            f.engagements.add(eng);
        }
        return f;
    }

    private static List<Map<String, Object>> fetchAllSteps(
            ExtoleClient client, ExtoleConfig config, String personId) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        try {
            HttpRequest req = simpleGet(config, ExtoleConstants.PEOPLE_PATH + '/' + personId + '/steps?limit=100');
            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                List<Object> items = (List<Object>) JSON.deserializeUntyped(res.getBody());
                for (Object o : items) out.add((Map<String, Object>) o);
            }
        } catch (Exception ignored) { }
        return out;
    }

    /**
     * Returns the full milestone set the campaign defines for FRIEND-journey
     * events, with completed first (in fire order) then pending (alpha). The
     * `allowed` map is {eventName → description} from business-event components
     * pre-filtered to journey=FRIEND. Description (when present) is the
     * preferred display label since Extole authors write it human-readable.
     */
    private static List<ExtolePersonCard.Milestone> filterStepsToMilestones(
            List<Map<String, Object>> allSteps, String campaignId, Map<String, String> allowed) {
        List<ExtolePersonCard.Milestone> out = new List<ExtolePersonCard.Milestone>();
        if (allowed == null || allowed.isEmpty()) return out;

        Map<String, ExtolePersonCard.Milestone> completedByName = new Map<String, ExtolePersonCard.Milestone>();
        for (Integer i = allSteps.size() - 1; i >= 0; i--) {
            Map<String, Object> m = allSteps[i];
            String name = (String) m.get('name');
            String stepCampaignId = (String) m.get('campaign_id');
            if (String.isBlank(name) || completedByName.containsKey(name)) continue;
            if (!allowed.containsKey(name)) continue;
            if (campaignId != null && stepCampaignId != null && !campaignId.equals(stepCampaignId)) continue;
            ExtolePersonCard.Milestone ms = new ExtolePersonCard.Milestone();
            ms.name        = name;
            ms.displayName = displayLabelFor(name, allowed.get(name));
            ms.eventDate   = (String) m.get('event_date');
            ms.quality     = (String) m.get('quality');
            ms.completed   = true;
            completedByName.put(name, ms);
        }
        out.addAll(completedByName.values());

        List<String> pendingNames = new List<String>();
        for (String n : allowed.keySet()) {
            if (!completedByName.containsKey(n)) pendingNames.add(n);
        }
        pendingNames.sort();
        for (String n : pendingNames) {
            ExtolePersonCard.Milestone ms = new ExtolePersonCard.Milestone();
            ms.name        = n;
            ms.displayName = displayLabelFor(n, allowed.get(n));
            ms.completed   = false;
            out.add(ms);
        }
        return out;
    }

    /** Humanize snake_case → Title Case for the primary label. Description
     *  (when present) is surfaced as a tooltip on the LWC, not the label. */
    private static String displayLabelFor(String name, String description) {
        return humanizeEventName(name);
    }

    /** Turns snake_case event names into Title Case display labels. */
    private static String humanizeEventName(String name) {
        if (String.isBlank(name)) return '';
        List<String> parts = name.split('_');
        List<String> capitalized = new List<String>();
        for (String p : parts) {
            if (String.isBlank(p)) continue;
            capitalized.add(p.substring(0, 1).toUpperCase() + p.substring(1).toLowerCase());
        }
        return String.join(capitalized, ' ');
    }

    private static ExtolePersonCard.IncomingReferral buildIncomingReferral(
            ExtoleClient client, ExtoleConfig config, Map<String, Object> rel) {
        ExtolePersonCard.IncomingReferral ir = new ExtolePersonCard.IncomingReferral();
        ir.advocatePersonId = (String) rel.get('other_person_id');
        ir.program          = (String) rel.get('program');
        ir.createdDate      = (String) rel.get('created_date');
        ir.shareableCode    = pullNamedValue(rel, 'shareable_code');
        // Resolve advocate identity (best-effort)
        try {
            HttpRequest req = simpleGet(config, ExtoleConstants.PEOPLE_PATH + '/' + ir.advocatePersonId);
            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                ir.email = (String) m.get('identity_key_value');
                ir.displayName = ir.email; // best-effort; data call can be added later
            }
        } catch (Exception ignored) { }
        return ir;
    }

    /**
     * One bulk SOQL each for Lead + Contact by email. Sets sfdcRecordId/sfdcObjectType
     * on every Friend and the IncomingReferral when an email matches an SFDC record.
     * Contact wins over Lead if both exist (Contacts are converted; more authoritative).
     */
    private static void attachSfdcRecordIds(ExtolePersonCard card) {
        Set<String> emails = new Set<String>();
        for (ExtolePersonCard.Friend f : card.friends) {
            if (String.isNotBlank(f.email)) emails.add(f.email.toLowerCase());
        }
        if (card.referredBy != null && String.isNotBlank(card.referredBy.email)) {
            emails.add(card.referredBy.email.toLowerCase());
        }
        if (emails.isEmpty()) return;

        Map<String, Map<String, String>> match = new Map<String, Map<String, String>>();
        for (Lead l : [SELECT Id, Email FROM Lead WHERE Email IN :emails WITH SECURITY_ENFORCED LIMIT 200]) {
            if (l.Email == null) continue;
            String key = l.Email.toLowerCase();
            if (!match.containsKey(key)) {
                match.put(key, new Map<String, String>{ 'id' => l.Id, 'type' => 'Lead' });
            }
        }
        for (Contact c : [SELECT Id, Email FROM Contact WHERE Email IN :emails WITH SECURITY_ENFORCED LIMIT 200]) {
            if (c.Email == null) continue;
            // Contact beats Lead on conflict
            match.put(c.Email.toLowerCase(), new Map<String, String>{ 'id' => c.Id, 'type' => 'Contact' });
        }

        for (ExtolePersonCard.Friend f : card.friends) {
            if (String.isBlank(f.email)) continue;
            Map<String, String> m = match.get(f.email.toLowerCase());
            if (m != null) {
                f.sfdcRecordId    = m.get('id');
                f.sfdcObjectType  = m.get('type');
            }
        }
        if (card.referredBy != null && String.isNotBlank(card.referredBy.email)) {
            Map<String, String> m = match.get(card.referredBy.email.toLowerCase());
            if (m != null) {
                card.referredBy.sfdcRecordId   = m.get('id');
                card.referredBy.sfdcObjectType = m.get('type');
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // Small helpers
    // ──────────────────────────────────────────────────────────────────────

    private static HttpRequest simpleGet(ExtoleConfig config, String path) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + path);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setTimeout(config.timeoutMs);
        return req;
    }

    private static String composeDisplayName(ExtolePerson p) {
        String name = ((p.firstName == null ? '' : p.firstName) + ' ' + (p.lastName == null ? '' : p.lastName)).trim();
        return String.isNotBlank(name) ? name : p.email;
    }

    /** Extracts {"name":"key","value":"X","scope":...} → "X" from a relationship/data map. */
    private static String pullNamedValue(Map<String, Object> parent, String key) {
        Object dataObj = parent.get('data');
        if (dataObj instanceof Map<String, Object>) {
            Map<String, Object> dataMap = (Map<String, Object>) dataObj;
            return nestedValue(dataMap, key);
        }
        return null;
    }

    private static String nestedValue(Map<String, Object> dataMap, String key) {
        Object entry = dataMap.get(key);
        if (entry instanceof Map<String, Object>) {
            return (String) ((Map<String, Object>) entry).get('value');
        }
        return null;
    }

    private static String formatRewardAmount(Map<String, Object> rewardMap) {
        // Reward amount shape varies — try face_value, then face_value_amount, then partner-side fields.
        Object faceValue = rewardMap.get('face_value');
        if (faceValue instanceof Map<String, Object>) {
            Map<String, Object> fv = (Map<String, Object>) faceValue;
            Object amount = fv.get('value');
            String currencyCode = (String) fv.get('currency');
            if (amount != null) return formatAmountWithCurrency(String.valueOf(amount), currencyCode);
        }
        return '';
    }

    private static String formatAmountWithCurrency(String amount, String currencyCode) {
        if ('USD'.equalsIgnoreCase(currencyCode)) return '$' + amount;
        if (String.isBlank(currencyCode)) return amount;
        return amount + ' ' + currencyCode;
    }

    private static String summarizeRewards(List<ExtolePersonCard.RewardSummary> rewards) {
        if (rewards == null || rewards.isEmpty()) return '';
        Integer paid = 0;
        for (ExtolePersonCard.RewardSummary r : rewards) {
            if ('PAID'.equalsIgnoreCase(r.state) || 'EARNED'.equalsIgnoreCase(r.state)) paid++;
        }
        if (paid == 0) return '';
        return paid + ' reward' + (paid == 1 ? '' : 's') + ' earned';
    }
}
