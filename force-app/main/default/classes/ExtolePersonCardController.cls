/**
 * ExtolePersonCardController
 *
 * Drives the per-person LWC on Lead and Contact record pages. Split into
 * three @AuraEnabled methods so the LWC can parallelize the expensive
 * per-friend fan-out:
 *
 *   1. getCardSkeleton(email)        — fast base payload: advocate identity,
 *                                      share links, rewards, referred-by,
 *                                      friend stubs with default-pending
 *                                      milestones, plus the per-campaign
 *                                      milestone allowlist (the heavy
 *                                      /v1/components fetch).
 *   2. getFriendDetail(personId, …)  — one friend's full record: identity
 *                                      (/persons/{id} + /data) + step
 *                                      progress (/steps) filtered through
 *                                      the allowlist + reward attribution.
 *                                      Fired in parallel from the LWC.
 *   3. attachSfdcLinks(emails)       — bulk SOQL cross-link by email. Fired
 *                                      once after all friend details resolve.
 *
 * All three are cacheable=true so repeat visits to the same record are
 * served from LWC platform cache.
 */
public with sharing class ExtolePersonCardController {

    private static final Integer MAX_FRIENDS = 10;

    // ──────────────────────────────────────────────────────────────────────
    // Phase 1: Skeleton
    // ──────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static ExtolePersonCard.Skeleton getCardSkeleton(String email) {
        ExtolePersonCard.Skeleton sk = new ExtolePersonCard.Skeleton();
        sk.email = email;
        if (String.isBlank(email)) return sk;

        try {
            ExtoleConfig config = new ExtoleConfig('Extole_API');
            ExtoleClient client = new ExtoleClient();

            // 1. Resolve advocate identity
            ExtolePerson advocate = resolvePerson(client, config, email);
            if (advocate == null) {
                return sk; // hasAnyData stays false → card self-hides
            }
            sk.personId    = advocate.id;
            sk.displayName = composeDisplayName(advocate);

            // 2-4. Fan-out: shareables, relationships, rewards
            List<ExtolePersonCard.ShareLink> shareLinks  = fetchShareLinks(client, config, advocate.id);
            Map<String, Object> relSplit                 = fetchRelationships(client, config, advocate.id);
            Map<String, List<Map<String, Object>>> outgoingByFriend =
                (Map<String, List<Map<String, Object>>>) relSplit.get('outgoingByFriend');
            List<Map<String, Object>> incomingRaw        = (List<Map<String, Object>>) relSplit.get('incoming');
            List<ExtolePersonCard.RewardSummary> rewards = fetchRewards(client, config, advocate.id);

            sk.shareLinks = shareLinks;
            sk.rewards    = rewards;

            // 5. Per-campaign milestone allowlists (the heavy fetch — done once
            //    here so all per-friend calls can reuse it).
            Set<String> campaignIds = new Set<String>();
            for (List<Map<String, Object>> rels : outgoingByFriend.values()) {
                for (Map<String, Object> rel : rels) {
                    String cid = (String) rel.get('campaign_id');
                    if (String.isNotBlank(cid)) campaignIds.add(cid);
                }
            }
            Map<String, Map<String, String>> milestonesByCampaign =
                fetchMilestoneAllowlists(client, config, campaignIds);
            String milestonesJson = JSON.serialize(milestonesByCampaign);
            String rewardsJson    = JSON.serialize(rewards);

            // 6. Build friend stubs: structure-only, milestones default pending.
            //    The LWC renders these immediately while it fans out detail calls.
            Integer count = 0;
            for (String friendPersonId : outgoingByFriend.keySet()) {
                if (count >= MAX_FRIENDS) break;
                List<Map<String, Object>> friendRels = outgoingByFriend.get(friendPersonId);

                ExtolePersonCard.Friend f = new ExtolePersonCard.Friend();
                f.friendPersonId = friendPersonId;
                f.displayName    = '';   // resolved in phase 2
                f.email          = null;
                for (Map<String, Object> rel : friendRels) {
                    ExtolePersonCard.CampaignEngagement eng = new ExtolePersonCard.CampaignEngagement();
                    eng.program       = (String) rel.get('program');
                    eng.campaignId    = (String) rel.get('campaign_id');
                    eng.createdDate   = (String) rel.get('created_date');
                    eng.shareableCode = pullNamedValue(rel, 'shareable_code');
                    Map<String, String> allowed = milestonesByCampaign.get(eng.campaignId);
                    eng.milestones    = defaultPendingMilestones(allowed);
                    f.engagements.add(eng);
                }
                sk.friends.add(f);

                ExtolePersonCard.FriendDetailRequest req = new ExtolePersonCard.FriendDetailRequest();
                req.friendPersonId = friendPersonId;
                req.relsJson       = JSON.serialize(friendRels);
                req.milestonesJson = milestonesJson;
                req.rewardsJson    = rewardsJson;
                sk.friendRequests.add(req);

                count++;
            }

            // 7. Referred-by (incoming): cheap, one /persons call. Stays in skeleton.
            if (incomingRaw != null && !incomingRaw.isEmpty()) {
                sk.referredBy = buildIncomingReferral(client, config, incomingRaw[0]);
            }

            sk.totalEarnedLabel = summarizeRewards(rewards);
            sk.hasAnyData = !shareLinks.isEmpty()
                || !sk.friends.isEmpty()
                || !rewards.isEmpty()
                || sk.referredBy != null;
        } catch (Exception e) {
            System.debug('ExtolePersonCardController.getCardSkeleton ERROR: ' + e.getMessage());
        }
        return sk;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Phase 2: Per-friend detail (parallelizable)
    // ──────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static ExtolePersonCard.Friend getFriendDetail(
            String friendPersonId, String relsJson, String milestonesJson, String rewardsJson) {

        ExtolePersonCard.Friend f = new ExtolePersonCard.Friend();
        f.friendPersonId = friendPersonId;
        if (String.isBlank(friendPersonId)) return f;

        try {
            ExtoleConfig config = new ExtoleConfig('Extole_API');
            ExtoleClient client = new ExtoleClient();

            // Resolve identity
            try {
                HttpRequest req = simpleGet(config, ExtoleConstants.PEOPLE_PATH + '/' + friendPersonId);
                HttpResponse res = client.send(config, req);
                if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                    Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    f.email = (String) m.get('identity_key_value');
                }
                HttpRequest dataReq = simpleGet(config, ExtoleConstants.PEOPLE_PATH + '/' + friendPersonId + '/data');
                HttpResponse dataRes = client.send(config, dataReq);
                if (dataRes.getStatusCode() >= 200 && dataRes.getStatusCode() < 300) {
                    Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(dataRes.getBody());
                    String first = nestedValue(dataMap, 'first_name');
                    String last  = nestedValue(dataMap, 'last_name');
                    if (String.isNotBlank(first) || String.isNotBlank(last)) {
                        f.displayName = ((first == null ? '' : first) + ' ' + (last == null ? '' : last)).trim();
                    }
                }
            } catch (Exception ignored) { }
            if (String.isBlank(f.displayName)) f.displayName = f.email != null ? f.email : friendPersonId;

            // Parse skeleton context
            List<Map<String, Object>> friendRels = parseRelList(relsJson);
            Map<String, Map<String, String>> milestonesByCampaign = parseMilestonesMap(milestonesJson);
            List<ExtolePersonCard.RewardSummary> advocateRewards = parseRewardsList(rewardsJson);

            // Fetch step progress (one /steps call regardless of how many engagements)
            List<Map<String, Object>> allSteps = fetchAllSteps(client, config, friendPersonId);

            // Build one engagement per relationship record
            for (Map<String, Object> rel : friendRels) {
                ExtolePersonCard.CampaignEngagement eng = new ExtolePersonCard.CampaignEngagement();
                eng.program        = (String) rel.get('program');
                eng.campaignId     = (String) rel.get('campaign_id');
                eng.createdDate    = (String) rel.get('created_date');
                eng.shareableCode  = pullNamedValue(rel, 'shareable_code');

                Map<String, String> allowed = milestonesByCampaign.get(eng.campaignId);
                eng.milestones = filterStepsToMilestones(allSteps, eng.campaignId, allowed);

                String causeEventId = (String) rel.get('cause_event_id');
                for (ExtolePersonCard.RewardSummary r : advocateRewards) {
                    if (r.causeEventId != null && causeEventId != null && r.causeEventId.equals(causeEventId)) {
                        eng.reward = r;
                        break;
                    }
                }
                f.engagements.add(eng);
            }
        } catch (Exception e) {
            System.debug('ExtolePersonCardController.getFriendDetail ERROR: ' + e.getMessage());
        }
        return f;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Phase 3: SFDC cross-link (one bulk SOQL after all friends resolve)
    // ──────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ExtolePersonCard.SfdcLink> attachSfdcLinks(List<String> emails) {
        List<ExtolePersonCard.SfdcLink> out = new List<ExtolePersonCard.SfdcLink>();
        if (emails == null || emails.isEmpty()) return out;

        Set<String> emailSet = new Set<String>();
        for (String e : emails) {
            if (String.isNotBlank(e)) emailSet.add(e.toLowerCase());
        }
        if (emailSet.isEmpty()) return out;

        // Contact wins over Lead on conflict (Contacts are converted, more authoritative).
        Map<String, Map<String, String>> match = new Map<String, Map<String, String>>();
        for (Lead l : [SELECT Id, Email FROM Lead WHERE Email IN :emailSet WITH SECURITY_ENFORCED LIMIT 200]) {
            if (l.Email == null) continue;
            String key = l.Email.toLowerCase();
            if (!match.containsKey(key)) {
                match.put(key, new Map<String, String>{ 'id' => l.Id, 'type' => 'Lead' });
            }
        }
        for (Contact c : [SELECT Id, Email FROM Contact WHERE Email IN :emailSet WITH SECURITY_ENFORCED LIMIT 200]) {
            if (c.Email == null) continue;
            match.put(c.Email.toLowerCase(), new Map<String, String>{ 'id' => c.Id, 'type' => 'Contact' });
        }
        for (String k : match.keySet()) {
            ExtolePersonCard.SfdcLink link = new ExtolePersonCard.SfdcLink();
            link.email      = k;
            link.recordId   = match.get(k).get('id');
            link.objectType = match.get(k).get('type');
            out.add(link);
        }
        return out;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ──────────────────────────────────────────────────────────────────────

    private static ExtolePerson resolvePerson(ExtoleClient client, ExtoleConfig config, String email) {
        HttpRequest req = ExtoleGetPersonRequest.byEmail(email).build(config);
        HttpResponse res = client.send(config, req);
        ExtoleGetPersonResponse resp = ExtoleGetPersonResponse.fromResponse(res);
        if (resp.person == null || String.isBlank(resp.person.id)) return null;

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
     * Fetch the FRIEND-journey business-event milestone allowlist for each
     * campaign. Streaming parse keeps each /v1/components response (often
     * 5MB+) within Apex heap limits.
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

    private static String extractJourneyFromVariables(JSONParser p) {
        String journey = null;
        p.nextToken();
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
            }
        }
        return journey;
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

    /** All allowed milestones rendered as pending — used for skeleton stubs
     *  before the friend's actual step progress is fetched. */
    private static List<ExtolePersonCard.Milestone> defaultPendingMilestones(Map<String, String> allowed) {
        List<ExtolePersonCard.Milestone> out = new List<ExtolePersonCard.Milestone>();
        if (allowed == null || allowed.isEmpty()) return out;
        List<String> names = new List<String>(allowed.keySet());
        names.sort();
        for (String n : names) {
            ExtolePersonCard.Milestone ms = new ExtolePersonCard.Milestone();
            ms.name        = n;
            ms.displayName = displayLabelFor(n, allowed.get(n));
            ms.completed   = false;
            out.add(ms);
        }
        return out;
    }

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

    private static String displayLabelFor(String name, String description) {
        return humanizeEventName(name);
    }

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
        try {
            HttpRequest req = simpleGet(config, ExtoleConstants.PEOPLE_PATH + '/' + ir.advocatePersonId);
            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                ir.email = (String) m.get('identity_key_value');
                ir.displayName = ir.email;
            }
        } catch (Exception ignored) { }
        return ir;
    }

    // ──────────────────────────────────────────────────────────────────────
    // JSON deserialization helpers (typed)
    // ──────────────────────────────────────────────────────────────────────

    @SuppressWarnings('PMD.ApexUnusedLocalVariable')
    private static List<Map<String, Object>> parseRelList(String relsJson) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (String.isBlank(relsJson)) return out;
        Object parsed = JSON.deserializeUntyped(relsJson);
        if (parsed instanceof List<Object>) {
            for (Object o : (List<Object>) parsed) {
                if (o instanceof Map<String, Object>) out.add((Map<String, Object>) o);
            }
        }
        return out;
    }

    private static Map<String, Map<String, String>> parseMilestonesMap(String milestonesJson) {
        Map<String, Map<String, String>> out = new Map<String, Map<String, String>>();
        if (String.isBlank(milestonesJson)) return out;
        Object parsed = JSON.deserializeUntyped(milestonesJson);
        if (!(parsed instanceof Map<String, Object>)) return out;
        Map<String, Object> top = (Map<String, Object>) parsed;
        for (String cid : top.keySet()) {
            Object nested = top.get(cid);
            Map<String, String> allowed = new Map<String, String>();
            if (nested instanceof Map<String, Object>) {
                Map<String, Object> innerMap = (Map<String, Object>) nested;
                for (String eventName : innerMap.keySet()) {
                    Object v = innerMap.get(eventName);
                    allowed.put(eventName, v == null ? null : String.valueOf(v));
                }
            }
            out.put(cid, allowed);
        }
        return out;
    }

    private static List<ExtolePersonCard.RewardSummary> parseRewardsList(String rewardsJson) {
        if (String.isBlank(rewardsJson)) return new List<ExtolePersonCard.RewardSummary>();
        try {
            return (List<ExtolePersonCard.RewardSummary>)
                JSON.deserialize(rewardsJson, List<ExtolePersonCard.RewardSummary>.class);
        } catch (Exception e) {
            return new List<ExtolePersonCard.RewardSummary>();
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

    private static String pullNamedValue(Map<String, Object> parent, String key) {
        Object dataObj = parent.get('data');
        if (dataObj instanceof Map<String, Object>) {
            return nestedValue((Map<String, Object>) dataObj, key);
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
