@IsTest
private class ExtolePersonCardControllerTest {
    private static final String REFERRERS_URL = '/relationships?my_roles=FRIEND&include_duplicate_identities=true&limit=100&offset=0';

    @IsTest
    static void testBlankEmailReturnsEmptyCard() {
        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            ''
        );
        Test.stopTest();

        System.assertEquals('', result.email);
        System.assertEquals(false, result.hasAnyData);
        System.assertEquals(0, result.shareLinks.size());
        System.assertEquals(0, result.friends.size());
        System.assertEquals(0, result.referrers.size());
    }

    @IsTest
    static void testPersonNotFoundReturnsEmptyCard() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, '[]')
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'nobody@example.com'
        );
        Test.stopTest();

        System.assertEquals('nobody@example.com', result.email);
        System.assertEquals(false, result.hasAnyData);
        System.assertEquals(0, result.friends.size());
    }

    @IsTest
    static void testCalloutErrorIsSwallowedAndReturnsEmptyCard() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(500, '{"error":"boom"}')
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(false, result.hasAnyData);
    }

    @IsTest
    static void testGetCardDataFullHappyPath() {
        Contact matchingFriend = new Contact(
            LastName = 'Friend',
            Email = 'friend@example.com'
        );
        insert matchingFriend;

        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(
                '/v5/persons/p_friend/data',
                200,
                '{"email":{"name":"email","value":"friend@example.com","scope":"PUBLIC"},' +
                    '"first_name":{"name":"first_name","value":"Fiona","scope":"PUBLIC"},' +
                    '"last_name":{"name":"last_name","value":"Friend","scope":"PUBLIC"}}'
            )
            .addPattern(
                '/v5/persons/p_referrer/data',
                200,
                '{"email":{"name":"email","value":"referrer@example.com","scope":"PUBLIC"}}'
            )
            .addPattern(
                '/v5/persons/p_friend/steps',
                200,
                '[{"name":"friend_signup","label":"Signed Up","event_date":"2026-01-02"},' +
                '{"name":"was_referred","label":"Was Referred","event_date":"2026-01-01"}]'
            )
            .addPattern('/v5/persons/p_referrer/steps', 200, '[]')
            .addPattern(
                '/v5/persons/p_friend',
                200,
                '{"id":"p_friend","identity_key":"email","identity_key_value":"friend@example.com"}'
            )
            .addPattern(
                '/v5/persons/p_referrer',
                200,
                '{"id":"p_referrer","identity_key":"email","identity_key_value":"referrer@example.com"}'
            )
            .addPattern(
                '/v5/persons/p_advocate/shareables',
                200,
                '[{"code":"ABC123","link":"https://refer.example.com/abc123","label":"Refer-a-Friend"}]'
            )
            .addPattern(
                '/v5/persons/p_advocate/relationships?limit=100&offset=0',
                200,
                '[{"my_role":"ADVOCATE","other_person_id":"p_friend","program":"referral-program"}]'
            )
            .addPattern(
                REFERRERS_URL,
                200,
                '[{"my_role":"FRIEND","other_person_id":"p_referrer","program":"referral-program"}]'
            )
            .addPattern(
                '/v5/persons/p_advocate/rewards?limit=100&offset=0',
                200,
                '[{"id":"r1","state":"EARNED","face_value":25,"face_value_type":"usd",' +
                    '"earned_date":"2026-01-01","program":"Referral Program","campaign_id":"c1",' +
                    '"data":{"other_person_id":{"name":"other_person_id","value":"p_friend"}}}]'
            )
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_advocate"}]'
            )
            .addPattern(
                '/v2/campaign-summaries',
                200,
                '[{"program_label":"referral-program","campaign_id":"c1","state":"LIVE"}]'
            )
            .addPattern(
                '/v2/campaigns/c1/controllers/built',
                200,
                '[{"name":"friend_signup","journey_names":["FRIEND"]}]'
            )
            .addPattern(
                '/v2/campaigns/c1/flow-steps/built',
                200,
                '[{"flow_path":"/business-events","step_name":"was_referred","name":"Was Referred","sequence":0},' +
                '{"flow_path":"/business-events","step_name":"friend_signup","name":"Signed Up","sequence":1}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(true, result.hasAnyData);
        System.assertEquals(1, result.shareLinks.size());
        System.assertEquals('ABC123', result.shareLinks[0].code);

        System.assertEquals(1, result.friends.size());
        ExtolePersonCard.Friend friend = result.friends[0];
        System.assertEquals('p_friend', friend.personId);
        System.assertEquals('friend@example.com', friend.email);
        System.assertEquals('Fiona Friend', friend.displayName);
        System.assertNotEquals(null, friend.reward);
        System.assertEquals('$25', friend.reward.amountLabel);
        System.assertEquals(matchingFriend.Id, friend.sfdcRecordId);
        System.assertEquals('Contact', friend.sfdcObjectType);

        System.assertEquals(1, friend.steps.size());
        System.assertEquals('friend_signup', friend.steps[0].name);
        System.assertEquals('2026-01-02', friend.steps[0].dateCompleted);

        System.assertEquals(1, result.totalReferrers);
        System.assertEquals('p_referrer', result.referrers[0].personId);
        System.assertEquals('referrer@example.com', result.referrers[0].email);
    }

    @IsTest
    static void testAttachSfdcLinksMatchesContactAndLead() {
        Contact c = new Contact(
            LastName = 'Test',
            Email = 'contact@example.com'
        );
        insert c;
        Lead l = new Lead(
            LastName = 'Test',
            Company = 'Acme',
            Email = 'lead@example.com'
        );
        insert l;

        Test.startTest();
        List<ExtolePersonCard.SfdcLink> links = ExtolePersonCardController.attachSfdcLinks(
            new List<String>{
                'contact@example.com',
                'lead@example.com',
                'nomatch@example.com'
            }
        );
        Test.stopTest();

        Map<String, ExtolePersonCard.SfdcLink> byEmail = new Map<String, ExtolePersonCard.SfdcLink>();
        for (ExtolePersonCard.SfdcLink link : links)
            byEmail.put(link.email, link);

        System.assertEquals(2, links.size());
        System.assertEquals(
            'Contact',
            byEmail.get('contact@example.com').objectType
        );
        System.assertEquals(c.Id, byEmail.get('contact@example.com').recordId);
        System.assertEquals('Lead', byEmail.get('lead@example.com').objectType);
        System.assertEquals(l.Id, byEmail.get('lead@example.com').recordId);
    }

    @IsTest
    static void testAttachSfdcLinksEmptyInput() {
        Test.startTest();
        List<ExtolePersonCard.SfdcLink> links = ExtolePersonCardController.attachSfdcLinks(
            new List<String>()
        );
        Test.stopTest();

        System.assertEquals(0, links.size());
    }

    @IsTest
    static void testAttachSfdcLinksLinksPersonAccountToAccount() {
        if (!ExtolePersonAccounts.isEnabled())
            return;
        Id personRt = (Id) Database.query(
                'SELECT Id FROM RecordType WHERE SobjectType = \'Account\' AND IsPersonType = true LIMIT 1'
            )[0]
            .get('Id');
        SObject pa = Schema.getGlobalDescribe().get('Account').newSObject();
        pa.put('RecordTypeId', personRt);
        pa.put('FirstName', 'Pat');
        pa.put('LastName', 'Person');
        pa.put('PersonEmail', 'person.account@example.com');
        insert pa;

        Test.startTest();
        List<ExtolePersonCard.SfdcLink> links = ExtolePersonCardController.attachSfdcLinks(
            new List<String>{ 'person.account@example.com' }
        );
        Test.stopTest();

        System.assertEquals(1, links.size());
        System.assertEquals('Account', links[0].objectType);
        System.assertEquals((Id) pa.get('Id'), links[0].recordId);
    }

    @IsTest
    static void testShareLinkFieldForAccountUsesPersonSuffix() {
        if (!ExtolePersonAccounts.isEnabled())
            return;
        String field = ExtoleBackfillController.getShareLinkFieldSetting(
            'Account'
        );
        System.assertEquals('Extole_Share_Link__pc', field);
    }

    private static String advocateRels(Integer first, Integer count) {
        String body = '[';
        for (Integer i = first; i < first + count; i++) {
            body +=
                (i > first ? ',' : '') +
                '{"my_role":"ADVOCATE","other_person_id":"p_f' +
                i +
                '","program":"referral-program"}';
        }
        return body + ']';
    }

    private static String pageUrl(String resource, Integer page) {
        return '/' + resource + '?limit=100&offset=' + (page * 100);
    }

    // Relationships served a hundred to a page.
    private static ExtoleConfigurableMock manyFriendsMock(Integer count) {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock();
        for (Integer page = 0; page * 100 < count; page++) {
            mock.addPattern(
                pageUrl('relationships', page),
                200,
                advocateRels(page * 100, Math.min(100, count - page * 100))
            );
        }
        return withPersonLookups(mock);
    }

    private static ExtoleConfigurableMock withPersonLookups(
        ExtoleConfigurableMock mock
    ) {
        return mock.addPattern(
                '/data',
                200,
                '{"email":{"name":"email","value":"friend@example.com","scope":"PUBLIC"}}'
            )
            .addPattern('/steps', 200, '[]')
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_advocate"}]'
            )
            .addPattern(
                '/v5/persons/p_f',
                200,
                '{"id":"p_f","identity_key":"email","identity_key_value":"friend@example.com"}'
            )
            .withDefault(200, '[]');
    }

    // Rewards that don't match a friend, only there to fill pages.
    private static String filler(Integer count) {
        String body = '[';
        for (Integer i = 0; i < count; i++) {
            body +=
                (i > 0 ? ',' : '') +
                '{"id":"r' +
                i +
                '","state":"CANCELED"}';
        }
        return body + ']';
    }

    private static String referrerRel(
        String otherId,
        String program,
        String identity
    ) {
        return '{"my_role":"FRIEND","other_person_id":"' +
            otherId +
            '","program":"' +
            program +
            '","other_person":{"id":"' +
            otherId +
            '","identity_key":{"name":"email"}' +
            (identity == null
                ? ''
                : ',"identity_key_value":"' + identity + '"') +
            '}}';
    }

    private static String referrerRels(Integer count, String program) {
        String body = '[';
        for (Integer i = 0; i < count; i++) {
            body +=
                (i > 0 ? ',' : '') +
                referrerRel('p_r' + i, program, 'r' + i + '@example.com');
        }
        return body + ']';
    }

    private static ExtoleConfigurableMock referrersMock(
        String friendRelationships,
        String referrerRelationships
    ) {
        return new ExtoleConfigurableMock()
            .addPattern(
                '/v5/persons/p_advocate/relationships?limit=100&offset=0',
                200,
                friendRelationships
            )
            .addPattern(REFERRERS_URL, 200, referrerRelationships)
            .addPattern(
                '/data',
                200,
                '{"email":{"name":"email","value":"looked@example.com","scope":"PUBLIC"},' +
                    '"first_name":{"name":"first_name","value":"Looked","scope":"PUBLIC"},' +
                    '"last_name":{"name":"last_name","value":"Up","scope":"PUBLIC"}}'
            )
            .addPattern('/steps', 200, '[]')
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_advocate"}]'
            )
            .addPattern('/v5/persons/p_r', 200, '{"id":"p_r"}')
            .withDefault(200, '[]');
    }

    private class RecordingMock implements HttpCalloutMock {
        ExtoleConfigurableMock answers;
        List<String> endpoints = new List<String>();
        RecordingMock(ExtoleConfigurableMock mock) {
            answers = mock;
        }
        public HttpResponse respond(HttpRequest req) {
            endpoints.add(req.getEndpoint());
            return answers.respond(req);
        }
    }

    @IsTest
    static void testReferrersAreReadWithDuplicateIdentitiesAndKeyedOnIdentity() {
        // p_r0 referred this person in two programs. p_r0b is a duplicate
        // person with p_r0's identity, in the first program. The two people
        // with no identity are two referrers.
        Test.setMock(
            HttpCalloutMock.class,
            referrersMock(
                '[]',
                '[' +
                    referrerRel('p_r0', 'prog-a', 'r0@example.com') +
                    ',' +
                    referrerRel('p_r1', 'prog-b', 'r1@example.com') +
                    ',' +
                    referrerRel('p_r0', 'prog-b', 'r0@example.com') +
                    ',' +
                    referrerRel('p_r0b', 'prog-a', 'r0@example.com') +
                    ',' +
                    referrerRel('p_n1', 'prog-a', null) +
                    ',' +
                    referrerRel('p_n2', 'prog-a', null) +
                    ']'
            )
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(true, result.hasAnyData);
        System.assertEquals(5, result.totalReferrers);
        List<String> seen = new List<String>();
        for (ExtolePersonCard.ReferredBy ref : result.referrerRefs) {
            seen.add(ref.personId + '|' + ref.program);
        }
        System.assertEquals(
            new List<String>{
                'p_r0|prog-a',
                'p_r1|prog-b',
                'p_r0|prog-b',
                'p_n1|prog-a',
                'p_n2|prog-a'
            },
            seen
        );
    }

    @IsTest
    static void testOnlyTheFirstReferrersAreLookedUpAndWithoutSteps() {
        RecordingMock mock = new RecordingMock(
            referrersMock('[]', referrerRels(7, 'prog-a'))
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(7, result.totalReferrers);
        System.assertEquals(7, result.referrerRefs.size());
        System.assertEquals(5, result.referrers.size());
        System.assertEquals('Looked Up', result.referrers[4].displayName);
        System.assertEquals('p_r4', result.referrers[4].personId);
        for (String endpoint : mock.endpoints) {
            System.assert(
                !endpoint.contains('/p_r5') && !endpoint.contains('/p_r6'),
                'looked up a referrer past the first five: ' + endpoint
            );
            System.assert(
                !(endpoint.contains('/p_r') && endpoint.contains('/steps')),
                'read a referrer\'s steps: ' + endpoint
            );
        }
    }

    @IsTest
    static void testReferrersPastTheFirstPageAreCounted() {
        ExtoleConfigurableMock mock = referrersMock(
            '[]',
            referrerRels(100, 'prog-a')
        );
        mock.addPattern(
            '&limit=100&offset=100',
            200,
            '[' + referrerRel('p_r100', 'prog-a', 'r100@example.com') + ']'
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(101, result.totalReferrers);
    }

    @IsTest
    static void testAFriendWhoIsAlsoAReferrerShowsInBoth() {
        // p_r0 is this person's friend in one program and referrer in another.
        Test.setMock(
            HttpCalloutMock.class,
            referrersMock(
                '[{"my_role":"ADVOCATE","other_person_id":"p_r0","program":"prog-a"}]',
                '[' + referrerRel('p_r0', 'prog-b', 'r0@example.com') + ']'
            )
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(1, result.friends.size());
        System.assertEquals(1, result.referrers.size());
        System.assertEquals('Looked Up', result.referrers[0].displayName);
        System.assertEquals('Looked Up', result.friends[0].displayName);
    }

    @IsTest
    static void testReferrerDetailsNameLinkAndSkipSteps() {
        Contact linked = new Contact(
            LastName = 'Linked',
            Email = 'looked@example.com'
        );
        insert linked;
        RecordingMock mock = new RecordingMock(referrersMock('[]', '[]'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<ExtolePersonCard.ReferredBy> out = ExtolePersonCardController.getReferrerDetails(
            new List<String>{ 'p_r5', 'p_r6', 'p_r5' }
        );
        Test.stopTest();

        System.assertEquals(2, out.size());
        System.assertEquals('p_r5', out[0].personId);
        System.assertEquals('Looked Up', out[0].displayName);
        System.assertEquals(linked.Id, out[0].sfdcRecordId);
        System.assertEquals('Contact', out[0].sfdcObjectType);
        for (String endpoint : mock.endpoints) {
            System.assert(
                !endpoint.contains('/steps'),
                'read steps: ' + endpoint
            );
        }
    }

    @IsTest
    static void testReferrerDetailsKeepsAReferrerWhoseLookupFails() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(500, '{}')
        );

        Test.startTest();
        List<ExtolePersonCard.ReferredBy> out = ExtolePersonCardController.getReferrerDetails(
            new List<String>{ 'p_r5' }
        );
        Test.stopTest();

        System.assertEquals(1, out.size());
        System.assertEquals('p_r5', out[0].personId);
        System.assertEquals(null, out[0].displayName);
    }

    @IsTest
    static void testEveryFriendIsKnownButOnlyTheFirstBatchIsLookedUp() {
        Test.setMock(HttpCalloutMock.class, manyFriendsMock(60));

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(60, result.totalFriends);
        System.assertEquals(60, result.friendRefs.size());
        System.assertEquals(5, result.friends.size());
        System.assertEquals('p_f0', result.friendRefs[0].personId);
        System.assertEquals('p_f59', result.friendRefs[59].personId);
    }

    @IsTest
    static void testFriendsPastTheFirstPageAreCounted() {
        Test.setMock(HttpCalloutMock.class, manyFriendsMock(120));

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(120, result.totalFriends);
        System.assertEquals(false, result.friendsTruncated);
    }

    @IsTest
    static void testAShortPageDoesNotEndThePaging() {
        // The API drops deleted persons after paging, so page one can come
        // back with 90 of 100 and page two still has friends.
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(pageUrl('relationships', 0), 200, advocateRels(0, 90))
            .addPattern(pageUrl('relationships', 1), 200, advocateRels(90, 30));
        Test.setMock(HttpCalloutMock.class, withPersonLookups(mock));

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(120, result.totalFriends);
    }

    @IsTest
    static void testFriendsAtThePageLimitAreFlaggedTruncated() {
        Test.setMock(HttpCalloutMock.class, manyFriendsMock(1000));

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(1000, result.totalFriends);
        System.assertEquals(true, result.friendsTruncated);
    }

    @IsTest
    static void testAFailedReadIsFlaggedTruncatedAndLeavesTheStatusUnknown() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(pageUrl('relationships', 0), 200, advocateRels(0, 100))
            .addPattern(pageUrl('relationships', 1), 500, '{"error":"boom"}')
            .addPattern('/rewards', 500, '{"error":"boom"}');
        Test.setMock(HttpCalloutMock.class, withPersonLookups(mock));

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(100, result.totalFriends);
        System.assertEquals(true, result.friendsTruncated);
        System.assertEquals(null, result.friendRefs[0].status);
    }

    @IsTest
    static void testGetFriendDetailsLoadsTheFriendsItIsGiven() {
        Test.setMock(HttpCalloutMock.class, manyFriendsMock(0));

        Test.startTest();
        List<ExtolePersonCard.Friend> friends = ExtolePersonCardController.getFriendDetails(
            new List<String>{ 'p_f7' },
            new List<String>{ 'referral-program' }
        );
        Test.stopTest();

        System.assertEquals(1, friends.size());
        System.assertEquals('p_f7', friends[0].personId);
        System.assertEquals('referral-program', friends[0].program);
        System.assertEquals('friend@example.com', friends[0].email);
    }

    @IsTest
    static void testGetFriendDetailsStopsAtTheCalloutLimit() {
        Test.setMock(HttpCalloutMock.class, manyFriendsMock(0));
        List<String> ids = new List<String>();
        for (Integer i = 0; i < 50; i++) {
            ids.add('p_f' + i);
        }

        Test.startTest();
        List<ExtolePersonCard.Friend> friends = ExtolePersonCardController.getFriendDetails(
            ids,
            null
        );
        Test.stopTest();

        // Three callouts a friend against a limit of 100.
        System.assertEquals(33, friends.size());
        System.assertEquals('p_f0', friends[0].personId);
        System.assertEquals('p_f32', friends[32].personId);
    }

    @IsTest
    static void testAFriendWhoseLookupFailsStaysInTheResultUnnamed() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern('/v5/persons/p_bad', 500, '{"error":"boom"}');
        Test.setMock(HttpCalloutMock.class, withPersonLookups(mock));

        Test.startTest();
        List<ExtolePersonCard.Friend> friends = ExtolePersonCardController.getFriendDetails(
            new List<String>{ 'p_f1', 'p_bad', 'p_f2' },
            null
        );
        Test.stopTest();

        System.assertEquals(3, friends.size());
        System.assertEquals('p_bad', friends[1].personId);
        System.assertEquals(null, friends[1].email);
        System.assertEquals('friend@example.com', friends[2].email);
    }

    @IsTest
    static void testGetFriendDetailsToleratesEmptyAndBlankInput() {
        System.assertEquals(
            0,
            ExtolePersonCardController.getFriendDetails(null, null).size()
        );
        System.assertEquals(
            0,
            ExtolePersonCardController.getFriendDetails(
                    new List<String>(),
                    new List<String>()
                )
                .size()
        );
        Test.setMock(HttpCalloutMock.class, manyFriendsMock(0));
        Test.startTest();
        System.assertEquals(
            0,
            ExtolePersonCardController.getFriendDetails(
                    new List<String>{ '', null },
                    null
                )
                .size()
        );
        Test.stopTest();
    }

    // ── Rewards in the shape Extole really returns ───────────────────────────

    // One friend whose reward is the given JSON row.
    private static ExtolePersonCard.Friend friendWithReward(String rewardRow) {
        Test.setMock(
            HttpCalloutMock.class,
            manyFriendsMock(1)
                .addPattern(
                    '/v5/persons/p_advocate/rewards?limit=100&offset=0',
                    200,
                    '[' + rewardRow + ']'
                )
        );
        return ExtolePersonCardController.getCardData('advocate@example.com')
            .friends[0];
    }

    @IsTest
    static void testRewardInTheShapeExtoleReturns() {
        Test.startTest();
        ExtolePersonCard.Friend f = friendWithReward(
            '{"id":"r9","state":"FULFILLED","face_value":5.0,"face_value_type":"USD",' +
                '"earned_date":"2026-11-18T08:21:25.891-08:00","program":"referral-program",' +
                '"data":{"other_person_id":{"name":"other_person_id","value":"p_f0"}}}'
        );
        Test.stopTest();

        System.assertNotEquals(null, f.reward);
        System.assertEquals('FULFILLED', f.reward.state);
        System.assertEquals('$5', f.reward.amountLabel);
        System.assertEquals(
            '2026-11-18T08:21:25.891-08:00',
            f.reward.dateEarned
        );
    }

    @IsTest
    static void testRewardedStatesAreEarnedSentRedeemedAndExpired() {
        Test.startTest();
        for (
            String state : new List<String>{
                'EARNED',
                'FULFILLED',
                'SENT',
                'REDEEMED',
                'EXPIRED'
            }
        ) {
            ExtolePersonCard.Friend f = friendWithReward(
                '{"id":"r1","state":"' +
                    state +
                    '","face_value":5,"face_value_type":"USD",' +
                    '"data":{"other_person_id":{"name":"other_person_id","value":"p_f0"}}}'
            );
            System.assertNotEquals(
                null,
                f.reward,
                state + ' is a reward that went out'
            );
        }
        ExtolePersonCard.Friend failed = friendWithReward(
            '{"id":"r1","state":"FAILED","face_value":5,"face_value_type":"USD",' +
            '"data":{"other_person_id":{"name":"other_person_id","value":"p_f0"}}}'
        );
        Test.stopTest();

        System.assertEquals(
            null,
            failed.reward,
            'a failed reward did not go out'
        );
    }

    @IsTest
    static void testAmountsReadTheWayAPersonWouldSayThem() {
        Test.startTest();
        System.assertEquals('$5', amountOf('5.0', 'USD'));
        System.assertEquals('$12.50', amountOf('12.5', 'USD'));
        System.assertEquals('20%', amountOf('20', 'PERCENT_OFF'));
        System.assertEquals('500 points', amountOf('500', 'POINTS'));
        System.assertEquals('£10', amountOf('10', 'GBP'));
        System.assertEquals('7 CHF', amountOf('7', 'CHF'));
        Test.stopTest();
    }

    @IsTest
    static void testMonthsAndPointsAreSingularForOne() {
        Test.startTest();
        System.assertEquals('1 month', amountOf('1', 'MONTH'));
        System.assertEquals('3 months', amountOf('3', 'MONTH'));
        System.assertEquals('1 point', amountOf('1', 'POINTS'));
        Test.stopTest();
    }

    private static String amountOf(String faceValue, String faceValueType) {
        return friendWithReward(
                '{"id":"r1","state":"EARNED","face_value":' +
                    faceValue +
                    ',"face_value_type":"' +
                    faceValueType +
                    '","data":{"other_person_id":{"name":"other_person_id","value":"p_f0"}}}'
            )
            .reward.amountLabel;
    }

    private static ExtolePersonCard.FriendRef refFor(
        ExtoleConfigurableMock mock
    ) {
        Test.setMock(HttpCalloutMock.class, mock);
        return ExtolePersonCardController.getCardData('advocate@example.com')
            .friendRefs[0];
    }

    @IsTest
    static void testAFriendWithNoDecisionIsNotRewardedYet() {
        Test.startTest();
        ExtolePersonCard.FriendRef ref = refFor(manyFriendsMock(1));
        Test.stopTest();

        System.assertEquals('pending', ref.status);
    }

    @IsTest
    static void testARewardThatWentOutMakesTheFriendRewarded() {
        Test.startTest();
        ExtolePersonCard.FriendRef ref = refFor(
            manyFriendsMock(1)
                .addPattern(
                    pageUrl('rewards', 0),
                    200,
                    '[{"id":"r1","state":"FULFILLED","face_value":5,"face_value_type":"USD",' +
                    '"data":{"other_person_id":{"value":"p_f0"}}}]'
                )
        );
        Test.stopTest();

        System.assertEquals('rewarded', ref.status);
    }

    @IsTest
    static void testAFailedOrCanceledRewardMakesTheFriendDeclined() {
        Test.startTest();
        for (
            String state : new List<String>{ 'FAILED', 'CANCELED', 'REVOKED' }
        ) {
            ExtolePersonCard.FriendRef ref = refFor(
                manyFriendsMock(1)
                    .addPattern(
                        pageUrl('rewards', 0),
                        200,
                        '[{"id":"r1","state":"' +
                            state +
                            '","face_value":5,"face_value_type":"USD",' +
                            '"data":{"other_person_id":{"value":"p_f0"}}}]'
                    )
            );
            System.assertEquals('declined', ref.status, state);
        }
        Test.stopTest();
    }

    private static String decisionsUrl(Integer page) {
        return '/steps?names=reward_evaluated&names=reward_manually_declined' +
            '&names=reward_manually_approved&limit=100&offset=' +
            (page * 100);
    }

    private static String decision(String name, String stamp, String state) {
        return '{"name":"' +
            name +
            '","event_date":"' +
            stamp +
            '",' +
            '"journey_key":{"name":"identity_person_id","value":"p_f0"},' +
            '"data":{"state":{"scope":"PRIVATE","value":"' +
            state +
            '"}}}';
    }

    // One friend, with the reward decisions answered first because the
    // generic /steps pattern in manyFriendsMock would otherwise match them.
    private static ExtoleConfigurableMock decisionsMock(
        Integer status,
        String decisions
    ) {
        return new ExtoleConfigurableMock()
            .addPattern(decisionsUrl(0), status, decisions)
            .addPattern(
                '/data',
                200,
                '{"email":{"name":"email","value":"friend@example.com","scope":"PUBLIC"}}'
            )
            .addPattern('/steps', 200, '[]')
            .addPattern(pageUrl('relationships', 0), 200, advocateRels(0, 1))
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_advocate"}]'
            )
            .addPattern(
                '/v5/persons/p_f',
                200,
                '{"id":"p_f","identity_key":"email","identity_key_value":"friend@example.com"}'
            )
            .withDefault(200, '[]');
    }

    @IsTest
    static void testADeclinedRewardDecisionMakesTheFriendDeclined() {
        Test.startTest();
        ExtolePersonCard.FriendRef ref = refFor(
            decisionsMock(
                200,
                '[' +
                    decision(
                        'reward_evaluated',
                        '2026-11-18T12:37:23.569-08:00',
                        'declined'
                    ) +
                    ']'
            )
        );
        Test.stopTest();

        System.assertEquals('declined', ref.status);
    }

    @IsTest
    static void testTheNewestDecisionWins() {
        Test.startTest();
        ExtolePersonCard.FriendRef approved = refFor(
            decisionsMock(
                200,
                '[' +
                    decision(
                        'reward_manually_approved',
                        '2026-11-19T09:00:00.000-08:00',
                        ''
                    ) +
                    ',' +
                    decision(
                        'reward_evaluated',
                        '2026-11-18T12:00:00.000-08:00',
                        'declined'
                    ) +
                    ']'
            )
        );
        System.assertEquals('pending', approved.status);

        ExtolePersonCard.FriendRef declined = refFor(
            decisionsMock(
                200,
                '[' +
                    decision(
                        'reward_manually_declined',
                        '2026-11-19T09:00:00.000-08:00',
                        ''
                    ) +
                    ',' +
                    decision(
                        'reward_evaluated',
                        '2026-11-18T12:00:00.000-08:00',
                        'approved'
                    ) +
                    ']'
            )
        );
        Test.stopTest();

        System.assertEquals('declined', declined.status);
    }

    @IsTest
    static void testARewardBeatsADeclineForTheSameFriend() {
        Test.startTest();
        ExtolePersonCard.FriendRef ref = refFor(
            manyFriendsMock(1)
                .addPattern(
                    pageUrl('rewards', 0),
                    200,
                    '[{"id":"r1","state":"EARNED","face_value":5,"face_value_type":"USD",' +
                        '"data":{"other_person_id":{"value":"p_f0"}}},' +
                        '{"id":"r2","state":"FAILED","face_value":5,"face_value_type":"USD",' +
                        '"data":{"other_person_id":{"value":"p_f0"}}}]'
                )
        );
        Test.stopTest();

        System.assertEquals('rewarded', ref.status);
    }

    @IsTest
    static void testAFailedDecisionReadLeavesTheStatusUnknown() {
        Test.startTest();
        ExtolePersonCard.FriendRef ref = refFor(decisionsMock(500, '{}'));
        Test.stopTest();

        System.assertEquals(null, ref.status);
    }

    @IsTest
    static void testDecisionsAtThePageLimitLeaveTheStatusUnknown() {
        // Three full pages of decisions for other friends: a decline for
        // this one could be on a page that was never read.
        String filler = '[';
        for (Integer i = 0; i < 100; i++) {
            filler +=
                (i > 0 ? ',' : '') +
                '{"name":"reward_evaluated","event_date":"2026-11-18T00:00:00.000-08:00"}';
        }
        filler += ']';
        ExtoleConfigurableMock capped = new ExtoleConfigurableMock();
        for (Integer page = 0; page < 3; page++) {
            capped.addPattern(decisionsUrl(page), 200, filler);
        }
        Test.startTest();
        ExtolePersonCard.FriendRef ref = refFor(
            withPersonLookups(
                capped.addPattern(
                    pageUrl('relationships', 0),
                    200,
                    advocateRels(0, 1)
                )
            )
        );
        Test.stopTest();

        System.assertEquals(null, ref.status);
    }

    @IsTest
    static void testADecisionNotKeyedByAFriendLeavesTheStatusUnknown() {
        // With rewardBehavior EVERY_ACTION the journey key is a step event,
        // so this decline can't be tied to a friend.
        Test.startTest();
        ExtolePersonCard.FriendRef ref = refFor(
            decisionsMock(
                200,
                '[{"name":"reward_evaluated","event_date":"2026-11-18T12:00:00.000-08:00",' +
                    '"journey_key":{"name":"step_event_id","value":"e1"},' +
                    '"data":{"state":{"scope":"PRIVATE","value":"declined"}}}]'
            )
        );
        Test.stopTest();

        System.assertEquals(null, ref.status);
    }

    @IsTest
    static void testRewardsAtThePageLimitLeaveOnlyTheStatusUnknown() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock();
        String firstPage =
            '[{"id":"r1","state":"EARNED","face_value":5,"face_value_type":"USD",' +
            '"data":{"other_person_id":{"name":"other_person_id","value":"p_f0"}}},' +
            filler(99).substring(1);
        mock.addPattern(pageUrl('rewards', 0), 200, firstPage);
        for (Integer page = 1; page < 10; page++) {
            mock.addPattern(pageUrl('rewards', page), 200, filler(100));
        }
        mock.addPattern(pageUrl('relationships', 0), 200, advocateRels(0, 2));
        Test.setMock(HttpCalloutMock.class, withPersonLookups(mock));

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals('rewarded', result.friendRefs[0].status);
        System.assertEquals(null, result.friendRefs[1].status);
    }

    @IsTest
    static void testADeclineThatWasReadShowsWhenRewardsAreAtThePageLimit() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock();
        for (Integer page = 0; page < 10; page++) {
            mock.addPattern(pageUrl('rewards', page), 200, filler(100));
        }
        mock.addPattern(
                decisionsUrl(0),
                200,
                '[' +
                    decision(
                        'reward_evaluated',
                        '2026-11-18T12:00:00.000-08:00',
                        'declined'
                    ) +
                    ']'
            )
            .addPattern(pageUrl('relationships', 0), 200, advocateRels(0, 2));
        Test.setMock(HttpCalloutMock.class, withPersonLookups(mock));

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals('declined', result.friendRefs[0].status);
        System.assertEquals(null, result.friendRefs[1].status);
    }

    private static ExtoleConfigurableMock amountsMock(String components) {
        return manyFriendsMock(1)
            .addPattern(
                '/v6/reward-suppliers/built',
                200,
                '[{"id":"s1","face_value":5,"face_value_type":"USD"},' +
                '{"id":"s2","face_value":10,"face_value_type":"USD"}]'
            )
            .addPattern(
                '/v2/campaign-summaries',
                200,
                '[{"campaign_id":"c1","program_label":"referral-program","state":"LIVE"}]'
            )
            .addPattern('/v2/campaigns/c1/components', 200, components);
    }

    private static String role(String id, String name) {
        return '{"id":"' +
            id +
            '","name":"' +
            name +
            '","types":["role-v10.0"],"component_ids":[]}';
    }

    private static String reward(String name, String roleId, String supplier) {
        return '{"id":"' +
            name +
            '","name":"' +
            name +
            '","types":["reward-v10.0"],"component_ids":["' +
            roleId +
            '"],' +
            '"variables":[{"name":"rewardSupplierId","values":{"default":"' +
            supplier +
            '"}}]}';
    }

    private static String advocateAmount(String components) {
        Test.setMock(HttpCalloutMock.class, amountsMock(components));
        return ExtolePersonCardController.getCardData('advocate@example.com')
            .advocateAmounts.get('referral-program');
    }

    @IsTest
    static void testTheAdvocatesAmountIsTheRewardUnderTheAdvocateRole() {
        Test.startTest();
        String amount = advocateAmount(
            '[' +
                role('ra', 'advocate') +
                ',' +
                role('rf', 'friend') +
                ',' +
                reward('first', 'rf', 's1') +
                ',' +
                reward('second', 'ra', 's2') +
                ']'
        );
        Test.stopTest();

        System.assertEquals('$10', amount);
    }

    @IsTest
    static void testNoAdvocateAmountWhenTheRoleHasMoreThanOneReward() {
        Test.startTest();
        String amount = advocateAmount(
            '[' +
                role('ra', 'advocate') +
                ',' +
                reward('signup', 'ra', 's1') +
                ',' +
                reward('purchase', 'ra', 's2') +
                ']'
        );
        Test.stopTest();

        System.assertEquals(null, amount);
    }

    @IsTest
    static void testAnExpressionFaceValueInTheUnbuiltSuppliersCannotBreakTheCard() {
        // face_value is a buildtime evaluatable: the raw list can hold an
        // expression string, the built list holds its value.
        Test.setMock(
            HttpCalloutMock.class,
            amountsMock(
                    '[' +
                        role('ra', 'advocate') +
                        ',' +
                        reward('r', 'ra', 's2') +
                        ']'
                )
                .addPattern(
                    '/v6/reward-suppliers',
                    200,
                    '[{"id":"s2","face_value":"javascript@buildtime:2*5","face_value_type":"USD"}]'
                )
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals('friend@example.com', result.friends[0].email);
        System.assertEquals(
            '$10',
            result.advocateAmounts.get('referral-program')
        );
    }

    @IsTest
    static void testARewardIsNotTheAdvocatesJustBecauseOfItsName() {
        Test.startTest();
        String amount = advocateAmount(
            '[' +
                role('ra', 'advocate') +
                ',' +
                role('rf', 'friend') +
                ',' +
                reward('advocate_reward', 'rf', 's1') +
                ']'
        );
        Test.stopTest();

        System.assertEquals(null, amount);
    }

    @IsTest
    static void testNoAdvocateAmountWhenTheCampaignHasNoAdvocateReward() {
        Test.startTest();
        String amount = advocateAmount(
            '[' + role('rf', 'friend') + ',' + reward('r', 'rf', 's1') + ']'
        );
        Test.stopTest();

        System.assertEquals(null, amount);
    }

    @IsTest
    static void testNoAmountWhenTheRewardSetupCannotBeRead() {
        Test.setMock(
            HttpCalloutMock.class,
            manyFriendsMock(1)
                .addPattern('/v6/reward-suppliers/built', 500, '{}')
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(0, result.advocateAmounts.size());
        System.assertEquals(1, result.friendRefs.size());
    }
}
