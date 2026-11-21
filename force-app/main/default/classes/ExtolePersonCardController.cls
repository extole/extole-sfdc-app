public with sharing class ExtolePersonCardController {
    private static final Integer FRIEND_BATCH = 5;
    // A friend costs about three callouts (person, data, steps) and a
    // transaction allows 100, so loading everyone at once is not possible.
    private static final Integer CALLOUTS_PER_FRIEND = 3;
    private static final Integer PAGE_SIZE = 100;
    private static final Integer MAX_PAGES = 10;
    private static final Set<String> DECLINED_STATES = new Set<String>{
        'FAILED',
        'CANCELED',
        'REVOKED'
    };
    private static final Integer MAX_DECISION_PAGES = 3;
    // Reward states for a reward that was given. EXPIRED can only follow
    // EARNED, FULFILLED or SENT, so the person did get one.
    private static final Set<String> REWARDED_STATES = new Set<String>{
        'EARNED',
        'FULFILLED',
        'SENT',
        'REDEEMED',
        'EXPIRED'
    };

    @AuraEnabled(cacheable=true)
    public static ExtolePersonCard.CardData getCardData(String email) {
        ExtolePersonCard.CardData result = new ExtolePersonCard.CardData();
        result.email = email;
        if (String.isBlank(email))
            return result;

        try {
            ExtoleConfig config = new ExtoleConfig('Extole_API');
            ExtoleClient client = new ExtoleClient();

            String personId = lookupPersonId(config, client, email);
            if (personId == null)
                return result;

            result.shareLinks = fetchShareLinks(config, client, personId);

            String personPath = ExtoleConstants.PEOPLE_PATH + '/' + personId;
            Pages relPages = fetchPages(
                config,
                client,
                personPath + '/relationships',
                '',
                MAX_PAGES
            );
            Pages rewardPages = fetchPages(
                config,
                client,
                personPath + '/rewards',
                '',
                MAX_PAGES
            );
            Pages decisionPages = fetchPages(
                config,
                client,
                personPath + '/steps',
                'journey_names=reward',
                MAX_DECISION_PAGES
            );
            result.friendsTruncated = relPages.truncated;
            result.rewardsTruncated = rewardPages.truncated;
            Boolean statusKnown =
                !rewardPages.truncated && !decisionPages.truncated;
            Set<String> declinedFriendIds = new Set<String>();
            Map<String, ExtolePersonCard.Reward> rewardsByFriendId = rewardsByFriend(
                rewardPages.rows,
                declinedFriendIds
            );
            addDeclinedEvaluations(decisionPages.rows, declinedFriendIds);

            Set<String> seenFriendIds = new Set<String>();
            List<String> personIdsToFetch = new List<String>();
            Map<String, String> personIdToProgram = new Map<String, String>();
            Set<String> friendPrograms = new Set<String>();

            for (Object relRaw : relPages.rows) {
                Map<String, Object> rel = (Map<String, Object>) relRaw;
                String role = getString(rel, 'my_role');
                String otherId = getString(rel, 'other_person_id');
                if (otherId == null)
                    continue;

                if (role == 'ADVOCATE' && !seenFriendIds.contains(otherId)) {
                    seenFriendIds.add(otherId);
                    ExtolePersonCard.FriendRef ref = new ExtolePersonCard.FriendRef();
                    ref.personId = otherId;
                    ref.program = getString(rel, 'program');
                    ref.reward = rewardsByFriendId.get(otherId);
                    ref.status = rewardStatus(
                        ref.reward,
                        declinedFriendIds.contains(otherId),
                        statusKnown
                    );
                    result.friendRefs.add(ref);
                    if (result.friends.size() < FRIEND_BATCH) {
                        ExtolePersonCard.Friend f = new ExtolePersonCard.Friend();
                        f.personId = otherId;
                        f.program = ref.program;
                        f.reward = ref.reward;
                        f.status = ref.status;
                        result.friends.add(f);
                        personIdsToFetch.add(otherId);
                        personIdToProgram.put(otherId, f.program);
                        if (String.isNotBlank(f.program))
                            friendPrograms.add(f.program);
                    }
                } else if (role == 'FRIEND' && result.referredBy == null) {
                    ExtolePersonCard.ReferredBy rb = new ExtolePersonCard.ReferredBy();
                    rb.personId = otherId;
                    rb.program = getString(rel, 'program');
                    result.referredBy = rb;
                    personIdsToFetch.add(otherId);
                    personIdToProgram.put(otherId, rb.program);
                }
            }

            result.totalFriends = result.friendRefs.size();

            Set<String> allPrograms = new Set<String>();
            for (ExtolePersonCard.FriendRef ref : result.friendRefs) {
                if (String.isNotBlank(ref.program))
                    allPrograms.add(ref.program);
            }
            Map<String, String> campaignByProgram = fetchProgramCampaigns(
                config,
                client,
                allPrograms
            );
            result.advocateAmounts = fetchAdvocateAmounts(
                config,
                client,
                campaignByProgram
            );
            Map<String, List<ExtolePersonCard.JourneyStep>> templateByProgram = fetchProgramTemplates(
                config,
                client,
                friendPrograms,
                campaignByProgram
            );
            Map<String, PersonProfile> profileById = fetchPersonProfiles(
                config,
                client,
                personIdsToFetch,
                personIdToProgram,
                templateByProgram
            );

            for (ExtolePersonCard.Friend f : result.friends) {
                PersonProfile profile = profileById.get(f.personId);
                if (profile != null) {
                    f.email = profile.email;
                    f.displayName = String.isNotBlank(profile.displayName)
                        ? profile.displayName
                        : profile.email;
                    f.steps = profile.steps;
                }
            }
            if (result.referredBy != null) {
                PersonProfile profile = profileById.get(
                    result.referredBy.personId
                );
                if (profile != null) {
                    result.referredBy.email = profile.email;
                    result.referredBy.displayName = String.isNotBlank(
                            profile.displayName
                        )
                        ? profile.displayName
                        : profile.email;
                }
            }

            result.hasAnyData =
                !result.shareLinks.isEmpty() ||
                !result.friends.isEmpty() ||
                result.referredBy != null;

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

    @AuraEnabled
    public static List<ExtolePersonCard.Friend> getFriendDetails(
        List<String> personIds,
        List<String> programs
    ) {
        List<ExtolePersonCard.Friend> out = new List<ExtolePersonCard.Friend>();
        if (personIds == null || personIds.isEmpty())
            return out;

        try {
            ExtoleConfig config = new ExtoleConfig('Extole_API');
            ExtoleClient client = new ExtoleClient();

            List<String> toFetch = new List<String>();
            Map<String, String> personIdToProgram = new Map<String, String>();
            Map<String, ExtolePersonCard.Friend> friendById = new Map<String, ExtolePersonCard.Friend>();
            Set<String> friendPrograms = new Set<String>();
            for (Integer i = 0; i < personIds.size(); i++) {
                String pid = personIds[i];
                if (String.isBlank(pid) || friendById.containsKey(pid))
                    continue;
                String program = programs != null &&
                    i < programs.size()
                    ? programs[i]
                    : null;
                ExtolePersonCard.Friend f = new ExtolePersonCard.Friend();
                f.personId = pid;
                f.program = String.isBlank(program) ? null : program;
                friendById.put(pid, f);
                toFetch.add(pid);
                personIdToProgram.put(pid, f.program);
                if (f.program != null)
                    friendPrograms.add(f.program);
            }

            Map<String, List<ExtolePersonCard.JourneyStep>> templateByProgram = fetchProgramTemplates(
                config,
                client,
                friendPrograms,
                fetchProgramCampaigns(config, client, friendPrograms)
            );
            Map<String, PersonProfile> profileById = fetchPersonProfiles(
                config,
                client,
                toFetch,
                personIdToProgram,
                templateByProgram
            );

            List<String> emails = new List<String>();
            for (String pid : toFetch) {
                PersonProfile profile = profileById.get(pid);
                if (profile == null)
                    continue;
                ExtolePersonCard.Friend f = friendById.get(pid);
                f.email = profile.email;
                f.displayName = String.isNotBlank(profile.displayName)
                    ? profile.displayName
                    : profile.email;
                f.steps = profile.steps;
                if (String.isNotBlank(f.email))
                    emails.add(f.email);
                out.add(f);
            }

            if (!emails.isEmpty()) {
                Map<String, ExtolePersonCard.SfdcLink> byEmail = new Map<String, ExtolePersonCard.SfdcLink>();
                for (ExtolePersonCard.SfdcLink l : attachSfdcLinks(emails)) {
                    if (l.email != null)
                        byEmail.put(l.email.toLowerCase(), l);
                }
                for (ExtolePersonCard.Friend f : out) {
                    ExtolePersonCard.SfdcLink l = f.email == null
                        ? null
                        : byEmail.get(f.email.toLowerCase());
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

    // ── Private API helpers ───────────────────────────────────────────────────

    private static String lookupPersonId(
        ExtoleConfig config,
        ExtoleClient client,
        String email
    ) {
        HttpRequest req = getRequest(
            config,
            ExtoleConstants.PEOPLE_PATH +
                '?identity_key_value=' +
                EncodingUtil.urlEncode(email, 'UTF-8') +
                '&limit=1'
        );

        HttpResponse res = client.send(config, req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
            return null;

        List<Object> persons = (List<Object>) JSON.deserializeUntyped(
            res.getBody()
        );
        if (persons == null || persons.isEmpty())
            return null;
        Map<String, Object> p = (Map<String, Object>) persons[0];
        return (String) p.get('id');
    }

    private static List<ExtolePersonCard.ShareLink> fetchShareLinks(
        ExtoleConfig config,
        ExtoleClient client,
        String personId
    ) {
        List<ExtolePersonCard.ShareLink> out = new List<ExtolePersonCard.ShareLink>();
        HttpRequest req = getRequest(
            config,
            ExtoleConstants.PEOPLE_PATH + '/' + personId + '/shareables'
        );

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

    private class Pages {
        List<Object> rows = new List<Object>();
        // True when there may be more than rows holds: the page limit was hit
        // or a read failed.
        Boolean truncated = false;
    }

    // Reads a list a hundred at a time. An empty page ends it: the API drops
    // deleted persons after paging, so a short page can still have more.
    private static Pages fetchPages(
        ExtoleConfig config,
        ExtoleClient client,
        String path,
        String query,
        Integer maxPages
    ) {
        Pages out = new Pages();
        for (Integer page = 0; page < maxPages; page++) {
            HttpResponse res = client.send(
                config,
                getRequest(
                    config,
                    path +
                        '?' +
                        (String.isBlank(query) ? '' : query + '&') +
                        'limit=' +
                        PAGE_SIZE +
                        '&offset=' +
                        (page * PAGE_SIZE)
                )
            );
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                out.truncated = true;
                return out;
            }
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(
                res.getBody()
            );
            if (raw == null || raw.isEmpty())
                return out;
            out.rows.addAll(raw);
        }
        out.truncated = true;
        return out;
    }

    private static Map<String, ExtolePersonCard.Reward> rewardsByFriend(
        List<Object> raw,
        Set<String> declinedFriendIds
    ) {
        Map<String, ExtolePersonCard.Reward> out = new Map<String, ExtolePersonCard.Reward>();
        for (Object o : raw) {
            Map<String, Object> m = (Map<String, Object>) o;
            String state = getString(m, 'state');
            Boolean rewarded = REWARDED_STATES.contains(state);
            if (!rewarded && !DECLINED_STATES.contains(state))
                continue;

            Object dataRaw = m.get('data');
            if (!(dataRaw instanceof Map<String, Object>))
                continue;
            Map<String, Object> data = (Map<String, Object>) dataRaw;
            String friendId = dataString(data, 'other_person_id');
            if (friendId == null)
                continue;
            if (!rewarded) {
                declinedFriendIds.add(friendId);
                continue;
            }
            if (!out.containsKey(friendId))
                out.put(friendId, buildReward(m, state));
        }
        return out;
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

    private static PersonProfile unnamedProfile() {
        return new PersonProfile(
            null,
            null,
            new List<ExtolePersonCard.JourneyStep>()
        );
    }

    private static Map<String, PersonProfile> fetchPersonProfiles(
        ExtoleConfig config,
        ExtoleClient client,
        List<String> personIds,
        Map<String, String> personIdToProgram,
        Map<String, List<ExtolePersonCard.JourneyStep>> templateByProgram
    ) {
        Map<String, PersonProfile> out = new Map<String, PersonProfile>();
        for (String pid : personIds) {
            if (
                Limits.getCallouts() + CALLOUTS_PER_FRIEND >
                Limits.getLimitCallouts()
            )
                break;
            try {
                HttpResponse res = client.send(
                    config,
                    ExtoleGetPersonRequest.byId(pid).build(config)
                );
                if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                    System.debug(
                        'fetchPersonProfiles ' +
                            pid +
                            ' status=' +
                            res.getStatusCode()
                    );
                    out.put(pid, unnamedProfile());
                    continue;
                }
                ExtolePerson p = ExtolePerson.fromMap(
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody())
                );

                HttpRequest dataReq = getRequest(
                    config,
                    ExtoleConstants.PEOPLE_PATH + '/' + pid + '/data'
                );
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

                List<ExtolePersonCard.JourneyStep> completedSteps = fetchFriendStepsData(
                    config,
                    client,
                    pid
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
                out.put(pid, unnamedProfile());
            }
        }
        return out;
    }

    private static Map<String, String> fetchProgramCampaigns(
        ExtoleConfig config,
        ExtoleClient client,
        Set<String> programs
    ) {
        Map<String, String> out = new Map<String, String>();
        if (programs.isEmpty())
            return out;
        HttpResponse res = client.send(
            config,
            getRequest(config, ExtoleConstants.CAMPAIGNS_SUMMARY_PATH)
        );
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300)
            return out;
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(
            res.getBody()
        );
        if (raw == null)
            return out;
        for (Object o : raw) {
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

    private static Map<String, List<ExtolePersonCard.JourneyStep>> fetchProgramTemplates(
        ExtoleConfig config,
        ExtoleClient client,
        Set<String> programs,
        Map<String, String> campaignByProgram
    ) {
        Map<String, List<ExtolePersonCard.JourneyStep>> out = new Map<String, List<ExtolePersonCard.JourneyStep>>();
        Map<String, String> programToCampaignId = new Map<String, String>();
        for (String prog : programs) {
            if (campaignByProgram.containsKey(prog))
                programToCampaignId.put(prog, campaignByProgram.get(prog));
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
        String pid
    ) {
        List<ExtolePersonCard.JourneyStep> out = new List<ExtolePersonCard.JourneyStep>();
        HttpRequest req = getRequest(
            config,
            ExtoleConstants.PEOPLE_PATH +
                '/' +
                pid +
                '/steps?limit=25&journey_names=FRIEND&is_primary=true'
        );
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
        HttpRequest req = getRequest(
            config,
            ExtoleConstants.CAMPAIGNS_PATH +
                '/' +
                campaignId +
                '/controllers/built'
        );
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
                    if ('FRIEND'.equals(String.valueOf(jn))) {
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
        HttpRequest req = getRequest(
            config,
            ExtoleConstants.CAMPAIGNS_PATH +
                '/' +
                campaignId +
                '/flow-steps/built'
        );
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
        for (ExtolePersonCard.JourneyStep s : completed) {
            if (s.name != null && s.dateCompleted != null)
                dateByName.put(s.name, s.dateCompleted);
        }
        List<ExtolePersonCard.JourneyStep> result = new List<ExtolePersonCard.JourneyStep>();
        for (ExtolePersonCard.JourneyStep template : flowSteps) {
            ExtolePersonCard.JourneyStep step = new ExtolePersonCard.JourneyStep();
            step.name = template.name;
            step.label = template.label;
            step.dateCompleted = dateByName.get(template.name);
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

    private static List<String> collectEmails(ExtolePersonCard.CardData data) {
        List<String> emails = new List<String>();
        if (data.friends != null) {
            for (ExtolePersonCard.Friend f : data.friends) {
                if (String.isNotBlank(f.email))
                    emails.add(f.email);
            }
        }
        if (
            data.referredBy != null && String.isNotBlank(data.referredBy.email)
        ) {
            emails.add(data.referredBy.email);
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
        if (data.referredBy != null && data.referredBy.email != null) {
            ExtolePersonCard.SfdcLink l = byEmail.get(
                data.referredBy.email.toLowerCase()
            );
            if (l != null) {
                data.referredBy.sfdcRecordId = l.recordId;
                data.referredBy.sfdcObjectType = l.objectType;
            }
        }
    }

    private static Map<String, String> fetchAdvocateAmounts(
        ExtoleConfig config,
        ExtoleClient client,
        Map<String, String> campaignByProgram
    ) {
        Map<String, String> out = new Map<String, String>();
        if (
            campaignByProgram.isEmpty() ||
            Limits.getCallouts() + 2 > Limits.getLimitCallouts()
        )
            return out;
        Map<String, String> supplierAmounts = fetchSupplierAmounts(
            config,
            client
        );
        if (supplierAmounts.isEmpty())
            return out;
        for (String program : campaignByProgram.keySet()) {
            if (Limits.getCallouts() >= Limits.getLimitCallouts())
                break;
            String amount = fetchAdvocateAmount(
                config,
                client,
                campaignByProgram.get(program),
                supplierAmounts
            );
            if (amount != null)
                out.put(program, amount);
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

    // The advocate's reward is the reward component installed under the
    // campaign's advocate role.
    private static String fetchAdvocateAmount(
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
        List<Object> components = (List<Object>) parsed;
        Set<String> advocateRoleIds = new Set<String>();
        for (Object o : components) {
            Map<String, Object> comp = (Map<String, Object>) o;
            if (
                hasType(comp, 'role-v10.0') &&
                'advocate'.equals(getString(comp, 'name'))
            )
                advocateRoleIds.add(getString(comp, 'id'));
        }
        for (Object o : components) {
            Map<String, Object> comp = (Map<String, Object>) o;
            if (!hasType(comp, 'reward-v10.0'))
                continue;
            Object parents = comp.get('component_ids');
            if (!(parents instanceof List<Object>))
                continue;
            for (Object parent : (List<Object>) parents) {
                if (advocateRoleIds.contains((String) parent))
                    return supplierAmounts.get(rewardSupplierId(comp));
            }
        }
        return null;
    }

    private static Boolean hasType(Map<String, Object> comp, String type) {
        Object types = comp.get('types');
        return types instanceof List<Object> &&
            ((List<Object>) types).contains(type);
    }

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

    // 'pending' only when every read that could show a reward or a decline
    // finished; otherwise the status is unknown and the card shows none.
    private static String rewardStatus(
        ExtolePersonCard.Reward reward,
        Boolean declined,
        Boolean known
    ) {
        if (reward != null)
            return 'rewarded';
        if (declined)
            return 'declined';
        return known ? 'pending' : null;
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

    // Adds the friends whose latest reward decision is a decline. A decision
    // is a reward_evaluated step (state "declined") or a manual decline or
    // approval; the newest one for a friend wins.
    private static void addDeclinedEvaluations(
        List<Object> steps,
        Set<String> declinedFriendIds
    ) {
        Map<String, String> latestDate = new Map<String, String>();
        Map<String, Boolean> latestDeclined = new Map<String, Boolean>();
        for (Object o : steps) {
            Map<String, Object> step = (Map<String, Object>) o;
            String name = getString(step, 'name');
            Boolean declined;
            if (name == 'reward_manually_declined')
                declined = true;
            else if (name == 'reward_manually_approved')
                declined = false;
            else if (name == 'reward_evaluated')
                declined = 'declined'.equals(decisionState(step.get('data')));
            else
                continue;

            Object key = step.get('journey_key');
            if (!(key instanceof Map<String, Object>))
                continue;
            String friendId = getString((Map<String, Object>) key, 'value');
            String stepDate = getString(step, 'event_date');
            if (friendId == null || stepDate == null)
                continue;
            if (
                !latestDate.containsKey(friendId) ||
                stepDate > latestDate.get(friendId)
            ) {
                latestDate.put(friendId, stepDate);
                latestDeclined.put(friendId, declined);
            }
        }
        for (String friendId : latestDeclined.keySet()) {
            if (latestDeclined.get(friendId))
                declinedFriendIds.add(friendId);
        }
    }

    private static ExtolePersonCard.Reward buildReward(
        Map<String, Object> m,
        String state
    ) {
        ExtoleReward reward = ExtoleReward.fromMap(m);
        ExtolePersonCard.Reward cardReward = new ExtolePersonCard.Reward();
        cardReward.state = state;
        cardReward.dateEarned = reward.dateEarned;
        if (reward.faceValue != null)
            cardReward.amountLabel = formatAmount(
                Decimal.valueOf(reward.faceValue),
                reward.faceValueType
            );
        return cardReward;
    }

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
        Map<String, String> units = new Map<String, String>{
            'points' => 'point',
            'month' => 'month'
        };
        String typeKey = faceValueType == null
            ? ''
            : faceValueType.toLowerCase();
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
        if (units.containsKey(typeKey))
            return num + ' ' + units.get(typeKey) + (faceValue == 1 ? '' : 's');
        return String.isBlank(faceValueType)
            ? num
            : num + ' ' + faceValueType.toUpperCase();
    }

    private static String dataString(Map<String, Object> data, String key) {
        Object v = data.get(key);
        if (!(v instanceof Map<String, Object>))
            return null;
        Object value = ((Map<String, Object>) v).get('value');
        return value instanceof String ? (String) value : null;
    }

    private static String getString(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v instanceof String ? (String) v : null;
    }
}
