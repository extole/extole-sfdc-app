public with sharing class ExtolePersonCardController {

    private static final Integer FRIEND_CAP = 25;

    @AuraEnabled(cacheable=true)
    public static ExtolePersonCard.CardData getCardData(String email) {
        ExtolePersonCard.CardData result = new ExtolePersonCard.CardData();
        result.email = email;
        if (String.isBlank(email)) return result;

        try {
            ExtoleConfig config = new ExtoleConfig('Extole_API');
            ExtoleClient client = new ExtoleClient();

            String personId = lookupPersonId(config, client, email);
            if (personId == null) return result;

            result.shareLinks = fetchShareLinks(config, client, personId);

            List<Map<String, Object>> rels = fetchRelationships(config, client, personId);
            Map<String, ExtolePersonCard.Reward> rewardsByFriendId = fetchRewards(config, client, personId);

            Set<String> seenFriendIds = new Set<String>();
            List<String> personIdsToFetch = new List<String>();
            Map<String, String> personIdToProgram = new Map<String, String>();
            Set<String> friendPrograms = new Set<String>();

            for (Map<String, Object> rel : rels) {
                String role    = getString(rel, 'my_role');
                String otherId = getString(rel, 'other_person_id');
                if (otherId == null) continue;

                if (role == 'ADVOCATE' && !seenFriendIds.contains(otherId) && result.friends.size() < FRIEND_CAP) {
                    seenFriendIds.add(otherId);
                    ExtolePersonCard.Friend f = new ExtolePersonCard.Friend();
                    f.personId = otherId;
                    f.program  = getString(rel, 'program');
                    f.reward   = rewardsByFriendId.get(otherId);
                    result.friends.add(f);
                    personIdsToFetch.add(otherId);
                    personIdToProgram.put(otherId, f.program);
                    if (String.isNotBlank(f.program)) friendPrograms.add(f.program);
                } else if (role == 'FRIEND' && result.referredBy == null) {
                    ExtolePersonCard.ReferredBy rb = new ExtolePersonCard.ReferredBy();
                    rb.personId = otherId;
                    rb.program  = getString(rel, 'program');
                    result.referredBy = rb;
                    personIdsToFetch.add(otherId);
                    personIdToProgram.put(otherId, rb.program);
                }
            }

            Map<String, List<ExtolePersonCard.JourneyStep>> templateByProgram =
                fetchProgramTemplates(config, client, friendPrograms);
            Map<String, PersonProfile> profileById = fetchPersonProfiles(config, client, personIdsToFetch, personIdToProgram, templateByProgram);

            for (ExtolePersonCard.Friend f : result.friends) {
                PersonProfile profile = profileById.get(f.personId);
                if (profile != null) {
                    f.email       = profile.email;
                    f.displayName = String.isNotBlank(profile.displayName) ? profile.displayName : profile.email;
                    f.steps       = profile.steps;
                }
            }
            if (result.referredBy != null) {
                PersonProfile profile = profileById.get(result.referredBy.personId);
                if (profile != null) {
                    result.referredBy.email       = profile.email;
                    result.referredBy.displayName = String.isNotBlank(profile.displayName) ? profile.displayName : profile.email;
                }
            }

            result.hasAnyData = !result.shareLinks.isEmpty() || !result.friends.isEmpty() || result.referredBy != null;

            List<String> emails = collectEmails(result);
            if (!emails.isEmpty()) {
                applySfdcLinks(result, attachSfdcLinks(emails));
            }
        } catch (Exception e) {
            System.debug('ExtolePersonCardController.getCardData ERROR: ' + e.getMessage());
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<ExtolePersonCard.SfdcLink> attachSfdcLinks(List<String> emails) {
        List<ExtolePersonCard.SfdcLink> out = new List<ExtolePersonCard.SfdcLink>();
        if (emails == null || emails.isEmpty()) return out;

        Set<String> emailSet = new Set<String>();
        for (String e : emails) {
            if (String.isNotBlank(e)) emailSet.add(e.toLowerCase());
        }
        if (emailSet.isEmpty()) return out;

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

    // ── Private API helpers ───────────────────────────────────────────────────

    private static String lookupPersonId(ExtoleConfig config, ExtoleClient client, String email) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.PEOPLE_PATH
            + '?identity_key_value=' + EncodingUtil.urlEncode(email, 'UTF-8') + '&limit=1');
        req.setMethod('GET');
        if (!config.isNamedCredentialMode()) req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);

        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return null;

        List<Object> persons = (List<Object>) JSON.deserializeUntyped(res.getBody());
        if (persons == null || persons.isEmpty()) return null;
        Map<String, Object> p = (Map<String, Object>) persons[0];
        return (String) p.get('id');
    }

    private static List<ExtolePersonCard.ShareLink> fetchShareLinks(ExtoleConfig config, ExtoleClient client, String personId) {
        List<ExtolePersonCard.ShareLink> out = new List<ExtolePersonCard.ShareLink>();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.PEOPLE_PATH + '/' + personId + '/shareables');
        req.setMethod('GET');
        if (!config.isNamedCredentialMode()) req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);

        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return out;

        List<Object> raw = (List<Object>) JSON.deserializeUntyped(res.getBody());
        if (raw == null) return out;
        for (Object o : raw) {
            Map<String, Object> m = (Map<String, Object>) o;
            ExtolePersonCard.ShareLink sl = new ExtolePersonCard.ShareLink();
            sl.code    = getString(m, 'code');
            sl.link    = getString(m, 'link');
            sl.program = getString(m, 'label');
            out.add(sl);
        }
        return out;
    }

    private static List<Map<String, Object>> fetchRelationships(ExtoleConfig config, ExtoleClient client, String personId) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.PEOPLE_PATH + '/' + personId + '/relationships?limit=50');
        req.setMethod('GET');
        if (!config.isNamedCredentialMode()) req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);

        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return out;

        List<Object> raw = (List<Object>) JSON.deserializeUntyped(res.getBody());
        if (raw == null) return out;
        for (Object o : raw) {
            out.add((Map<String, Object>) o);
        }
        return out;
    }

    private static Map<String, ExtolePersonCard.Reward> fetchRewards(ExtoleConfig config, ExtoleClient client, String personId) {
        Map<String, ExtolePersonCard.Reward> out = new Map<String, ExtolePersonCard.Reward>();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.PEOPLE_PATH + '/' + personId + '/rewards?limit=50');
        req.setMethod('GET');
        if (!config.isNamedCredentialMode()) req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);

        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return out;

        List<Object> raw = (List<Object>) JSON.deserializeUntyped(res.getBody());
        if (raw == null) return out;
        for (Object o : raw) {
            Map<String, Object> m = (Map<String, Object>) o;
            String state = getString(m, 'state');
            if (state != 'SENT' && state != 'EARNED' && state != 'PAID') continue;

            Object dataRaw = m.get('data');
            if (!(dataRaw instanceof Map<String, Object>)) continue;
            Map<String, Object> data = (Map<String, Object>) dataRaw;
            String friendId = getString(data, 'other_person_id');
            if (friendId == null || out.containsKey(friendId)) continue;

            ExtolePersonCard.Reward r = new ExtolePersonCard.Reward();
            r.rewardId      = getString(m, 'reward_id');
            r.state         = state;
            r.faceValueType = getString(m, 'face_value_type');
            r.dateEarned    = getString(m, 'date_earned');
            r.programLabel  = getString(m, 'program_label');
            r.campaignId    = getString(m, 'campaign_id');
            Object fv = m.get('face_value');
            if (fv != null) {
                try { r.faceValue = Decimal.valueOf(String.valueOf(fv)); } catch (Exception ignored) {}
            }
            if (r.faceValue != null) {
                Map<String, String> SYMBOLS = new Map<String, String>{
                    'usd' => '$', 'gbp' => '£', 'eur' => '€', 'jpy' => '¥', 'percent_off' => '%'
                };
                String sym = SYMBOLS.containsKey(r.faceValueType) ? SYMBOLS.get(r.faceValueType) : (r.faceValueType != null ? r.faceValueType : '');
                r.amountLabel = sym + String.valueOf(r.faceValue.setScale(0, System.RoundingMode.HALF_UP));
            }
            out.put(friendId, r);
        }
        return out;
    }

    private class PersonProfile {
        String email;
        String displayName;
        List<ExtolePersonCard.JourneyStep> steps;
        PersonProfile(String e, String d, List<ExtolePersonCard.JourneyStep> s) {
            email = e; displayName = d; steps = s;
        }
    }

    private static Map<String, PersonProfile> fetchPersonProfiles(
        ExtoleConfig config, ExtoleClient client,
        List<String> personIds, Map<String, String> personIdToProgram,
        Map<String, List<ExtolePersonCard.JourneyStep>> templateByProgram
    ) {
        Map<String, PersonProfile> out = new Map<String, PersonProfile>();
        for (String pid : personIds) {
            try {
                HttpResponse res = client.send(config, ExtoleGetPersonRequest.byId(pid).build(config));
                if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                    System.debug('fetchPersonProfiles ' + pid + ' status=' + res.getStatusCode());
                    continue;
                }
                ExtolePerson p = ExtolePerson.fromMap(
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody()));

                HttpRequest dataReq = new HttpRequest();
                dataReq.setEndpoint(config.getEndpoint() + ExtoleConstants.PEOPLE_PATH + '/' + pid + '/data');
                dataReq.setMethod('GET');
                if (!config.isNamedCredentialMode()) dataReq.setHeader('Authorization', config.getAuthHeader());
                dataReq.setTimeout(config.timeoutMs);
                HttpResponse dataRes = client.send(config, dataReq);
                if (dataRes.getStatusCode() >= 200 && dataRes.getStatusCode() < 300) {
                    p.applyData((Map<String, Object>) JSON.deserializeUntyped(dataRes.getBody()));
                }

                List<ExtolePersonCard.JourneyStep> completedSteps = fetchFriendStepsData(config, client, pid);
                List<ExtolePersonCard.JourneyStep> steps = completedSteps;
                String prog = personIdToProgram.get(pid);
                if (prog != null && templateByProgram.containsKey(prog) && !templateByProgram.get(prog).isEmpty()) {
                    steps = mergeSteps(templateByProgram.get(prog), completedSteps);
                }
                out.put(pid, new PersonProfile(p.email, buildDisplayName(p), steps));
            } catch (Exception e) {
                System.debug('fetchPersonProfiles ERROR for ' + pid + ': ' + e.getMessage());
            }
        }
        return out;
    }

    private static Map<String, List<ExtolePersonCard.JourneyStep>> fetchProgramTemplates(
        ExtoleConfig config, ExtoleClient client, Set<String> programs
    ) {
        Map<String, List<ExtolePersonCard.JourneyStep>> out = new Map<String, List<ExtolePersonCard.JourneyStep>>();
        if (programs.isEmpty()) return out;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.CAMPAIGNS_SUMMARY_PATH);
        req.setMethod('GET');
        if (!config.isNamedCredentialMode()) req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);

        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return out;

        List<Object> raw = (List<Object>) JSON.deserializeUntyped(res.getBody());
        if (raw == null) return out;

        // Build program → campaignId, preferring LIVE state
        Map<String, String> programToCampaignId = new Map<String, String>();
        for (Object o : raw) {
            Map<String, Object> c = (Map<String, Object>) o;
            String prog = getString(c, 'program_label');
            if (!programs.contains(prog)) continue;
            String cid = getString(c, 'campaign_id');
            if (cid == null) continue;
            if (!programToCampaignId.containsKey(prog) || 'LIVE'.equals(getString(c, 'state'))) {
                programToCampaignId.put(prog, cid);
            }
        }

        for (String prog : programToCampaignId.keySet()) {
            String cid = programToCampaignId.get(prog);
            Set<String> friendControllerNames = fetchFriendControllerStepNames(config, client, cid);
            out.put(prog, fetchCampaignFlowSteps(config, client, cid, friendControllerNames));
        }
        return out;
    }

    // Extole system steps — referral attribution and click-tracking infrastructure, never user-facing milestones.
    private static final Set<String> ATTRIBUTION_STEPS = new Set<String>{
        'was_referred', 'friend_confirmed',
        'friend_click', 'share_click', 'share_clicked', 'share_destination_rendered'
    };

    private static List<ExtolePersonCard.JourneyStep> fetchFriendStepsData(ExtoleConfig config, ExtoleClient client, String pid) {
        List<ExtolePersonCard.JourneyStep> out = new List<ExtolePersonCard.JourneyStep>();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.PEOPLE_PATH + '/' + pid
            + '/steps?limit=25&journey_names=FRIEND&is_primary=true');
        req.setMethod('GET');
        if (!config.isNamedCredentialMode()) req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);
        try {
            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return out;
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(res.getBody());
            if (raw == null) return out;
            for (Object o : raw) {
                Map<String, Object> s = (Map<String, Object>) o;
                String name = getString(s, 'name');
                if (name == null || ATTRIBUTION_STEPS.contains(name)) continue;
                ExtolePersonCard.JourneyStep step = new ExtolePersonCard.JourneyStep();
                step.name          = name;
                String apiLabel    = getString(s, 'label');
                step.label         = String.isNotBlank(apiLabel) ? apiLabel : prettifyStepName(name);
                step.dateCompleted = getString(s, 'event_date');
                out.add(step);
            }
        } catch (Exception e) {
            System.debug('fetchFriendStepsData ERROR for ' + pid + ': ' + e.getMessage());
        }
        return out;
    }

    private static Set<String> fetchFriendControllerStepNames(ExtoleConfig config, ExtoleClient client, String campaignId) {
        Set<String> names = new Set<String>();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.CAMPAIGNS_PATH + '/' + campaignId + '/controllers');
        req.setMethod('GET');
        if (!config.isNamedCredentialMode()) req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);
        try {
            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return names;
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(res.getBody());
            if (raw == null) return names;
            for (Object o : raw) {
                Map<String, Object> c = (Map<String, Object>) o;
                Object jnRaw = c.get('journey_names');
                if (!(jnRaw instanceof List<Object>)) continue;
                for (Object jn : (List<Object>) jnRaw) {
                    if ('FRIEND'.equals(String.valueOf(jn))) {
                        String cname = getString(c, 'name');
                        if (cname != null) names.add(cname);
                        break;
                    }
                }
            }
        } catch (Exception e) {
            System.debug('fetchFriendControllerStepNames ERROR campaign=' + campaignId + ': ' + e.getMessage());
        }
        return names;
    }

    private static List<ExtolePersonCard.JourneyStep> fetchCampaignFlowSteps(
        ExtoleConfig config, ExtoleClient client, String campaignId, Set<String> friendStepNames
    ) {
        List<ExtolePersonCard.JourneyStep> out = new List<ExtolePersonCard.JourneyStep>();
        if (friendStepNames.isEmpty()) return out;
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.CAMPAIGNS_PATH + '/' + campaignId + '/flow-steps/built');
        req.setMethod('GET');
        if (!config.isNamedCredentialMode()) req.setHeader('Authorization', config.getAuthHeader());
        req.setTimeout(config.timeoutMs);
        try {
            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return out;
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(res.getBody());
            if (raw == null) return out;
            List<Map<String, Object>> filtered = new List<Map<String, Object>>();
            for (Object o : raw) {
                Map<String, Object> fs = (Map<String, Object>) o;
                if (!'/business-events'.equals(getString(fs, 'flow_path'))) continue;
                String stepName = getString(fs, 'step_name');
                if (stepName == null || ATTRIBUTION_STEPS.contains(stepName)) continue;
                if (!friendStepNames.contains(stepName)) continue;
                filtered.add(fs);
            }
            // sort by sequence (bubble sort)
            for (Integer i = 0; i < filtered.size() - 1; i++) {
                for (Integer j = 0; j < filtered.size() - 1 - i; j++) {
                    if (getInteger(filtered[j], 'sequence') > getInteger(filtered[j + 1], 'sequence')) {
                        Map<String, Object> tmp = filtered[j];
                        filtered[j] = filtered[j + 1];
                        filtered[j + 1] = tmp;
                    }
                }
            }
            for (Map<String, Object> fs : filtered) {
                ExtolePersonCard.JourneyStep step = new ExtolePersonCard.JourneyStep();
                step.name  = getString(fs, 'step_name');
                String apiLabel = getString(fs, 'name');
                step.label = String.isNotBlank(apiLabel) ? apiLabel : prettifyStepName(step.name);
                out.add(step);
            }
        } catch (Exception e) {
            System.debug('fetchCampaignFlowSteps ERROR campaign=' + campaignId + ': ' + e.getMessage());
        }
        return out;
    }

    private static List<ExtolePersonCard.JourneyStep> mergeSteps(
        List<ExtolePersonCard.JourneyStep> flowSteps,
        List<ExtolePersonCard.JourneyStep> completed
    ) {
        Map<String, String> dateByName = new Map<String, String>();
        for (ExtolePersonCard.JourneyStep s : completed) {
            if (s.name != null && s.dateCompleted != null) dateByName.put(s.name, s.dateCompleted);
        }
        List<ExtolePersonCard.JourneyStep> result = new List<ExtolePersonCard.JourneyStep>();
        for (ExtolePersonCard.JourneyStep template : flowSteps) {
            ExtolePersonCard.JourneyStep step = new ExtolePersonCard.JourneyStep();
            step.name          = template.name;
            step.label         = template.label;
            step.dateCompleted = dateByName.get(template.name);
            result.add(step);
        }
        return result;
    }

    private static Integer getInteger(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v instanceof Integer) return (Integer) v;
        if (v instanceof Decimal) return ((Decimal) v).intValue();
        return 0;
    }

    private static String prettifyStepName(String name) {
        if (String.isBlank(name)) return name;
        String result = '';
        for (String part : name.split('_')) {
            if (String.isNotBlank(part)) {
                result += (result.length() > 0 ? ' ' : '')
                    + part.substring(0, 1).toUpperCase()
                    + part.substring(1).toLowerCase();
            }
        }
        return result;
    }

    private static String buildDisplayName(ExtolePerson p) {
        String name = '';
        if (String.isNotBlank(p.firstName)) name = p.firstName;
        if (String.isNotBlank(p.lastName))  name = (name + ' ' + p.lastName).trim();
        return String.isNotBlank(name) ? name : p.email;
    }

    // ── Shared helpers ────────────────────────────────────────────────────────

    private static List<String> collectEmails(ExtolePersonCard.CardData data) {
        List<String> emails = new List<String>();
        if (data.friends != null) {
            for (ExtolePersonCard.Friend f : data.friends) {
                if (String.isNotBlank(f.email)) emails.add(f.email);
            }
        }
        if (data.referredBy != null && String.isNotBlank(data.referredBy.email)) {
            emails.add(data.referredBy.email);
        }
        return emails;
    }

    private static void applySfdcLinks(ExtolePersonCard.CardData data, List<ExtolePersonCard.SfdcLink> links) {
        if (links == null || links.isEmpty()) return;
        Map<String, ExtolePersonCard.SfdcLink> byEmail = new Map<String, ExtolePersonCard.SfdcLink>();
        for (ExtolePersonCard.SfdcLink l : links) {
            if (l.email != null) byEmail.put(l.email.toLowerCase(), l);
        }
        if (data.friends != null) {
            for (ExtolePersonCard.Friend f : data.friends) {
                if (f.email == null) continue;
                ExtolePersonCard.SfdcLink l = byEmail.get(f.email.toLowerCase());
                if (l != null) { f.sfdcRecordId = l.recordId; f.sfdcObjectType = l.objectType; }
            }
        }
        if (data.referredBy != null && data.referredBy.email != null) {
            ExtolePersonCard.SfdcLink l = byEmail.get(data.referredBy.email.toLowerCase());
            if (l != null) { data.referredBy.sfdcRecordId = l.recordId; data.referredBy.sfdcObjectType = l.objectType; }
        }
    }

    private static String getString(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v instanceof String ? (String) v : null;
    }
}
