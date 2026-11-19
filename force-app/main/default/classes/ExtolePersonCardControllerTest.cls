@IsTest
private class ExtolePersonCardControllerTest {
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
        System.assertEquals(null, result.referredBy);
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
                '[{"name":"friend_signup","label":"Signed Up","event_date":"2026-01-02","quality":"LOW"},' +
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
                '/v5/persons/p_advocate/relationships',
                200,
                '[{"my_role":"ADVOCATE","other_person_id":"p_friend","program":"referral-program"},' +
                '{"my_role":"FRIEND","other_person_id":"p_referrer","program":"referral-program"}]'
            )
            .addPattern(
                '/v5/persons/p_advocate/rewards',
                200,
                '[{"reward_id":"r1","state":"EARNED","face_value":25,"face_value_type":"usd",' +
                    '"date_earned":"2026-01-01","program_label":"Referral Program","campaign_id":"c1",' +
                    '"data":{"other_person_id":"p_friend"}}]'
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
        System.assertEquals('r1', friend.reward.rewardId);
        System.assertEquals('$25', friend.reward.amountLabel);
        System.assertEquals(matchingFriend.Id, friend.sfdcRecordId);
        System.assertEquals('Contact', friend.sfdcObjectType);

        System.assertEquals(1, friend.steps.size());
        System.assertEquals('friend_signup', friend.steps[0].name);
        System.assertEquals('2026-01-02', friend.steps[0].dateCompleted);
        // Completed, but it failed Extole's quality checks.
        System.assertEquals(true, friend.steps[0].failed);

        System.assertNotEquals(null, result.referredBy);
        System.assertEquals('p_referrer', result.referredBy.personId);
        System.assertEquals('referrer@example.com', result.referredBy.email);
    }

    @IsTest
    static void testFirstBatchLoadsAndRestAreReferences() {
        // 25 friends: only the first batch gets details, all 25 are returned as references.
        String rels = '[';
        for (Integer i = 0; i < 25; i++) {
            rels +=
                (i > 0 ? ',' : '') +
                '{"my_role":"ADVOCATE","other_person_id":"p_f' +
                i +
                '","program":"referral-program"}';
        }
        rels += ']';
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern('/v5/persons/p_advocate/relationships', 200, rels)
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_advocate"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(25, result.totalFriends);
        System.assertEquals(25, result.friendRefs.size());
        System.assertEquals(
            ExtolePersonCardController.FRIEND_BATCH,
            result.friends.size()
        );
        System.assertEquals('p_f0', result.friends[0].personId);
        System.assertEquals(true, result.hasAnyData);
    }

    private static String stepJson(
        String name,
        String friendId,
        String eventDate,
        String state
    ) {
        return '{"name":"' +
            name +
            '","event_date":"' +
            eventDate +
            '","journey_key":{"name":"identity_person_id","value":"' +
            friendId +
            '"},"data":{"state":{"scope":"PRIVATE","value":"' +
            state +
            '"}}}';
    }

    @IsTest
    static void testRewardStatusRewardedDeclinedPending() {
        String rels = '[';
        List<String> ids = new List<String>{
            'p_a',
            'p_b',
            'p_c',
            'p_d',
            'p_e',
            'p_f',
            'p_g'
        };
        for (Integer i = 0; i < ids.size(); i++) {
            rels +=
                (i > 0 ? ',' : '') +
                '{"my_role":"ADVOCATE","other_person_id":"' +
                ids[i] +
                '","program":"referral-program"}';
        }
        rels += ']';
        // a: EARNED row. b: FAILED row. f: FAILED row and a FULFILLED row.
        // g: REDEEMED row.
        String rewards =
            '[{"reward_id":"r1","state":"EARNED","face_value":25,"face_value_type":"usd","data":{"other_person_id":"p_a"}},' +
            '{"reward_id":"r2","state":"FAILED","data":{"other_person_id":"p_b"}},' +
            '{"reward_id":"r3","state":"FAILED","data":{"other_person_id":"p_f"}},' +
            '{"reward_id":"r4","state":"FULFILLED","face_value":5,"face_value_type":"usd","data":{"other_person_id":"p_f"}},' +
            '{"reward_id":"r5","state":"REDEEMED","face_value":5,"face_value_type":"usd","data":{"other_person_id":"p_g"}},' +
            '{"reward_id":"r6","state":"PENDING","data":{"other_person_id":"p_e"}}]';
        // c: declined evaluation. d: declined, then manually approved later.
        // e: approved evaluation, no reward row yet.
        String steps =
            '[' +
            stepJson(
                'reward_evaluated',
                'p_c',
                '2026-01-02T00:00:00Z',
                'declined'
            ) +
            ',' +
            stepJson(
                'reward_evaluated',
                'p_d',
                '2026-01-02T00:00:00Z',
                'declined'
            ) +
            ',' +
            stepJson(
                'reward_manually_approved',
                'p_d',
                '2026-01-03T00:00:00Z',
                'approved'
            ) +
            ',' +
            stepJson(
                'reward_evaluated',
                'p_e',
                '2026-01-02T00:00:00Z',
                'approved'
            ) +
            ',' +
            stepJson(
                'reward_evaluation_started',
                'p_a',
                '2026-01-02T00:00:00Z',
                'declined'
            ) +
            ']';
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern('/v5/persons/p_advocate/relationships', 200, rels)
            .addPattern('/v5/persons/p_advocate/rewards', 200, rewards)
            .addPattern('/v5/persons/p_advocate/steps', 200, steps)
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_advocate"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        Map<String, ExtolePersonCard.FriendRef> byId = new Map<String, ExtolePersonCard.FriendRef>();
        for (ExtolePersonCard.FriendRef r : result.friendRefs)
            byId.put(r.personId, r);
        System.assertEquals('rewarded', byId.get('p_a').status);
        System.assertEquals('declined', byId.get('p_b').status);
        System.assertEquals('declined', byId.get('p_c').status);
        // A later manual approval undoes the decline.
        System.assertEquals('pending', byId.get('p_d').status);
        System.assertEquals('pending', byId.get('p_e').status);
        // A reward that went out wins over a failed one.
        System.assertEquals('rewarded', byId.get('p_f').status);
        System.assertEquals('r4', byId.get('p_f').reward.rewardId);
        System.assertEquals('rewarded', byId.get('p_g').status);
        // Declined friends carry no reward amount.
        System.assertEquals(null, byId.get('p_b').reward);
    }

    @IsTest
    static void testRewardStatusSurvivesDecisionLookupFailure() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(
                '/v5/persons/p_advocate/relationships',
                200,
                '[{"my_role":"ADVOCATE","other_person_id":"p_a","program":"referral-program"}]'
            )
            .addPattern('/v5/persons/p_advocate/steps', 500, 'boom')
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_advocate"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(1, result.friendRefs.size());
        System.assertEquals('pending', result.friendRefs[0].status);
    }

    @IsTest
    static void testStepsThatFailedQualityAreMarkedFailed() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(
                '/v5/persons/p_q/steps',
                200,
                '[{"name":"friend_signup","label":"Signed Up","event_date":"2026-01-02","quality":"LOW"},' +
                    '{"name":"lead_created","label":"Lead Created","event_date":"2026-01-03","quality":"HIGH"},' +
                    '{"name":"opportunity_created","label":"Opportunity Created","event_date":"2026-01-04"}]'
            )
            .addPattern(
                '/v5/persons/p_q/data',
                200,
                '{"email":{"name":"email","value":"q@example.com","scope":"PUBLIC"}}'
            )
            .addPattern(
                '/v5/persons/p_q',
                200,
                '{"id":"p_q","identity_key":"email","identity_key_value":"q@example.com"}'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<ExtolePersonCard.Friend> friends = ExtolePersonCardController.getFriendDetails(
            new List<String>{ 'p_q' },
            new List<String>{ 'referral-program' },
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(1, friends.size());
        Map<String, Boolean> failedByName = new Map<String, Boolean>();
        for (ExtolePersonCard.JourneyStep st : friends[0].steps)
            failedByName.put(st.name, st.failed);
        System.assertEquals(true, failedByName.get('friend_signup'));
        System.assertEquals(false, failedByName.get('lead_created'));
        // No quality reported counts as passing.
        System.assertEquals(false, failedByName.get('opportunity_created'));
    }

    @IsTest
    static void testRewardInTheShapeExtoleReturns() {
        // Copied from a live reward: data entries are {name, value} objects,
        // the type is upper case, and the date and id use different keys.
        String reward =
            '[{"id":"43a39c568fe5c8f78b63597e","face_value":5.0,"face_value_type":"USD",' +
            '"state":"FULFILLED","earned_date":"2026-11-18T08:21:25.891-08:00",' +
            '"data":{"other_person_id":{"name":"other_person_id","value":"p_a"}}}]';
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(
                '/v5/persons/p_advocate/relationships',
                200,
                '[{"my_role":"ADVOCATE","other_person_id":"p_a","program":"referral-program"}]'
            )
            .addPattern('/v5/persons/p_advocate/rewards', 200, reward)
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_advocate"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        ExtolePersonCard.FriendRef ref = result.friendRefs[0];
        System.assertEquals('rewarded', ref.status);
        System.assertEquals('$5', ref.reward.amountLabel);
        System.assertEquals('43a39c568fe5c8f78b63597e', ref.reward.rewardId);
        System.assertEquals(
            '2026-11-18T08:21:25.891-08:00',
            ref.reward.dateEarned
        );
    }

    @IsTest
    static void testProfileLinkCarriesTheClientIdFromTheToken() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(
                '/v4/tokens',
                200,
                '{"type":"USER","client_id":"1214577210","scopes":["CLIENT_ADMIN"]}'
            )
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_advocate"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(
            'https://my.extole.com/profiles/view/p_advocate?client_id=1214577210',
            result.profileUrl
        );
    }

    @IsTest
    static void testProfileLinkStillWorksWhenTheTokenLookupFails() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern('/v4/tokens', 403, '{"code":"access_denied"}')
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_advocate"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(
            'https://my.extole.com/profiles/view/p_advocate',
            result.profileUrl
        );
    }

    @IsTest
    static void testProfileLinkReadsTheClientIdFromAListToo() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern('/v4/tokens', 200, '[{"client_id":"42"}]')
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_advocate"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assert(result.profileUrl.endsWith('?client_id=42'));
    }

    @IsTest
    static void testProfileUrlEncodesIdsAndSkipsBlankPerson() {
        System.assertEquals(
            null,
            ExtolePersonCardController.profileUrl('', '1')
        );
        System.assertEquals(
            'https://my.extole.com/profiles/view/a%2Fb?client_id=c%26d',
            ExtolePersonCardController.profileUrl('a/b', 'c&d')
        );
    }

    private static ExtoleConfigurableMock friendMock(
        String rewards,
        String steps
    ) {
        return new ExtoleConfigurableMock()
            .addPattern(
                '/v5/persons/p_me/relationships',
                200,
                '[{"my_role":"FRIEND","other_person_id":"p_adv","program":"referral-program"}]'
            )
            .addPattern('/v5/persons/p_me/rewards', 200, rewards)
            .addPattern(
                '/v5/persons/p_me/steps?journey_names=reward',
                200,
                steps
            )
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_me"}]'
            )
            .withDefault(200, '[]');
    }

    @IsTest
    static void testFriendsOwnRewardIsRewarded() {
        // The reward is keyed on the friend themself, as Extole records it.
        Test.setMock(
            HttpCalloutMock.class,
            friendMock(
                '[{"id":"r1","face_value":5.0,"face_value_type":"USD","state":"FULFILLED",' +
                    '"program":"referral-program","earned_date":"2026-11-18T08:21:25.891-08:00",' +
                    '"journey_key":{"name":"identity_person_id","value":"p_me"},' +
                    '"data":{"other_person_id":{"name":"other_person_id","value":"p_adv"}}}]',
                '[]'
            )
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'friend@example.com'
        );
        Test.stopTest();

        System.assertEquals(1, result.ownPrograms.size());
        System.assertEquals('referral-program', result.ownPrograms[0].program);
        System.assertEquals('rewarded', result.ownPrograms[0].status);
        System.assertEquals('$5', result.ownPrograms[0].reward.amountLabel);
    }

    @IsTest
    static void testFriendsOwnRewardIsDeclined() {
        Test.setMock(
            HttpCalloutMock.class,
            friendMock(
                '[]',
                '[{"name":"reward_evaluated","program":"referral-program","event_date":"2026-11-18T12:37:23.569-08:00",' +
                    '"journey_key":{"name":"identity_person_id","value":"p_me"},' +
                    '"data":{"state":{"scope":"PRIVATE","value":"declined"}}}]'
            )
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'friend@example.com'
        );
        Test.stopTest();

        System.assertEquals(1, result.ownPrograms.size());
        System.assertEquals('declined', result.ownPrograms[0].status);
        System.assertEquals(null, result.ownPrograms[0].reward);
    }

    @IsTest
    static void testAnIssuedRewardBelongsToTheReferrerItNames() {
        Test.setMock(
            HttpCalloutMock.class,
            friendMock(
                '[{"id":"r1","face_value":5.0,"face_value_type":"USD","state":"FULFILLED",' +
                    '"program":"referral-program","earned_date":"2026-11-18T08:21:25.891-08:00",' +
                    '"journey_key":{"name":"identity_person_id","value":"p_me"},' +
                    '"data":{"other_person_id":{"name":"other_person_id","value":"p_adv"}}}]',
                '[]'
            )
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'friend@example.com'
        );
        Test.stopTest();

        System.assertEquals('p_adv', result.ownPrograms[0].rewardReferrerId);
    }

    @IsTest
    static void testAPendingRewardBelongsToTheReferrerWithARewardJourney() {
        // Two referrers in one program; only p_adv has a reward journey.
        Test.setMock(
            HttpCalloutMock.class,
            friendMock('[]', '[]')
                .addPattern(
                    '/v5/persons/p_me/journeys?names=reward',
                    200,
                    '[{"id":"j1","name":"reward","program":"referral-program","data":{' +
                        '"other_person_role":{"value":"ADVOCATE"},' +
                        '"other_person_id":{"value":"p_adv"}}},' +
                        '{"id":"j2","name":"reward","program":"referral-program","data":{' +
                        '"other_person_id":{"value":"p_someone_else"}}}]'
                )
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'friend@example.com'
        );
        Test.stopTest();

        System.assertEquals('pending', result.ownPrograms[0].status);
        System.assertEquals('p_adv', result.ownPrograms[0].rewardReferrerId);
    }

    @IsTest
    static void testRewardIsNotAttributedWhenTwoReferrersHaveJourneys() {
        Test.setMock(
            HttpCalloutMock.class,
            friendMock('[]', '[]')
                .addPattern(
                    '/v5/persons/p_me/journeys?names=reward',
                    200,
                    '[{"id":"j1","name":"reward","program":"referral-program","data":{' +
                        '"other_person_role":{"value":"ADVOCATE"},"other_person_id":{"value":"p_adv"}}},' +
                        '{"id":"j2","name":"reward","program":"referral-program","data":{' +
                        '"other_person_role":{"value":"ADVOCATE"},"other_person_id":{"value":"p_other"}}}]'
                )
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'friend@example.com'
        );
        Test.stopTest();

        System.assertEquals(null, result.ownPrograms[0].rewardReferrerId);
    }

    private static String ownRewardAmount(
        String faceValue,
        String faceValueType
    ) {
        Test.setMock(
            HttpCalloutMock.class,
            friendMock(
                '[{"id":"r1","face_value":' +
                    faceValue +
                    ',"face_value_type":"' +
                    faceValueType +
                    '","state":"EARNED","program":"referral-program",' +
                    '"journey_key":{"name":"identity_person_id","value":"p_me"},' +
                    '"data":{"other_person_id":{"value":"p_adv"}}}]',
                '[]'
            )
        );
        return ExtolePersonCardController.getCardData('friend@example.com')
            .ownPrograms[0]
            .reward.amountLabel;
    }

    @IsTest
    static void testAmountsReadTheWayAPersonWouldSayThem() {
        Test.startTest();
        System.assertEquals('$5', ownRewardAmount('5.0', 'USD'));
        System.assertEquals('$12.50', ownRewardAmount('12.5', 'USD'));
        System.assertEquals('20%', ownRewardAmount('20', 'PERCENT_OFF'));
        System.assertEquals('500 points', ownRewardAmount('500', 'POINTS'));
        System.assertEquals('£10', ownRewardAmount('10', 'GBP'));
        System.assertEquals('7 CHF', ownRewardAmount('7', 'CHF'));
        Test.stopTest();
    }

    @IsTest
    static void testReferredFriendWithNoDecisionIsNotRewardedYet() {
        Test.setMock(HttpCalloutMock.class, friendMock('[]', '[]'));

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'friend@example.com'
        );
        Test.stopTest();

        System.assertEquals('pending', result.ownPrograms[0].status);
    }

    @IsTest
    static void testPersonWithNoReferralAndNoRewardShowsNoOwnStatus() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .addPattern(
                    '/v5/persons?identity_key_value=',
                    200,
                    '[{"id":"p_me"}]'
                )
                .withDefault(200, '[]')
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'someone@example.com'
        );
        Test.stopTest();

        System.assertEquals(0, result.ownPrograms.size());
    }

    @IsTest
    static void testOffersCardListsARewardFromAProgramWithNoReferral() {
        // A reward from a program with no referral has no other person.
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .addPattern(
                    '/v5/persons/p_me/rewards',
                    200,
                    '[{"id":"r9","face_value":10,"face_value_type":"USD","state":"SENT","earned_date":"2026-11-01"}]'
                )
                .addPattern(
                    '/v5/persons?identity_key_value=',
                    200,
                    '[{"id":"p_me"}]'
                )
                .withDefault(200, '[]')
        );

        Test.startTest();
        ExtolePersonCard.OffersData result = ExtolePersonCardController.getOffersData(
            'member@example.com'
        );
        Test.stopTest();

        System.assertEquals(1, result.programs.size());
        System.assertEquals(null, result.programs[0].program);
        System.assertEquals('rewarded', result.programs[0].status);
        System.assertEquals('$10', result.programs[0].reward.amountLabel);
        System.assertEquals(true, result.hasAnyData);
    }

    @IsTest
    static void testFriendSeesTheirOwnSteps() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(
                '/v5/persons/p_me/relationships',
                200,
                '[{"my_role":"FRIEND","other_person_id":"p_adv","program":"referral-program"}]'
            )
            .addPattern(
                '/v5/persons/p_me/data',
                200,
                '{"email":{"name":"email","value":"friend@example.com","scope":"PUBLIC"}}'
            )
            .addPattern(
                '/v5/persons/p_me/steps?limit=25',
                200,
                '[{"name":"friend_signup","label":"Signed Up","event_date":"2026-01-02","quality":"HIGH"},' +
                '{"name":"lead_created","label":"Lead Created","event_date":"2026-01-03","quality":"LOW"}]'
            )
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_me","identity_key":"email","identity_key_value":"friend@example.com"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'friend@example.com'
        );
        Test.stopTest();

        List<ExtolePersonCard.JourneyStep> steps = result.ownPrograms[0].steps;
        System.assertEquals(2, steps.size());
        System.assertEquals('friend_signup', steps[0].name);
        System.assertEquals(false, steps[0].failed);
        // Completed, but it failed Extole's quality checks.
        System.assertEquals(true, steps[1].failed);
    }

    @IsTest
    static void testOffersCardShowsAnOfferWithItsStepsAndReward() {
        // No relationships at all: the person earned a reward in an offer program.
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(
                '/v5/persons/p_me/rewards',
                200,
                '[{"id":"r1","face_value":5.0,"face_value_type":"USD","state":"FULFILLED",' +
                    '"program":"simple-offer-test","earned_date":"2026-11-18T14:51:18.936-08:00",' +
                    '"journey_key":{"name":"identity_person_id","value":"p_me"}}]'
            )
            .addPattern(
                '/v5/persons/p_me/data',
                200,
                '{"email":{"name":"email","value":"member@example.com","scope":"PUBLIC"}}'
            )
            .addPattern(
                '/v5/persons/p_me/steps?limit=25',
                200,
                '[{"name":"opportunity_closedwon","event_date":"2026-11-18","quality":"HIGH"}]'
            )
            .addPattern(
                '/v2/campaign-summaries',
                200,
                '[{"campaign_id":"c9","program_label":"simple-offer-test","state":"LIVE"}]'
            )
            .addPattern(
                '/v2/campaigns/c9/controllers/built',
                200,
                '[{"name":"lead_qualified","journey_names":["PARTICIPANT"]},' +
                '{"name":"opportunity_closedwon","journey_names":["PARTICIPANT"]}]'
            )
            .addPattern(
                '/v2/campaigns/c9/flow-steps/built',
                200,
                '[{"flow_path":"/business-events","step_name":"opportunity_closedwon","name":"Closed Won","sequence":3},' +
                '{"flow_path":"/business-events","step_name":"lead_qualified","name":"Qualified","sequence":1}]'
            )
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_me","identity_key":"email","identity_key_value":"member@example.com"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.OffersData result = ExtolePersonCardController.getOffersData(
            'member@example.com'
        );
        Test.stopTest();

        System.assertEquals(true, result.hasAnyData);
        System.assertEquals(1, result.programs.size());
        ExtolePersonCard.OwnProgram own = result.programs[0];
        System.assertEquals('rewarded', own.status);
        System.assertEquals('$5', own.reward.amountLabel);
        System.assertEquals('simple-offer-test', own.program);
        // The offer's own flow gives the labels and the step not reached yet.
        System.assertEquals(2, own.steps.size());
        System.assertEquals('Qualified', own.steps[0].label);
        System.assertEquals(null, own.steps[0].dateCompleted);
        System.assertEquals('Closed Won', own.steps[1].label);
        System.assertEquals('2026-11-18', own.steps[1].dateCompleted);
    }

    @IsTest
    static void testPersonInTwoProgramsGetsABlockForEach() {
        // Referred in one program, rewarded in it; also earned an offer's reward.
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(
                '/v5/persons/p_me/relationships',
                200,
                '[{"my_role":"FRIEND","other_person_id":"p_adv1","program":"refer-a-friend"},' +
                '{"my_role":"FRIEND","other_person_id":"p_adv2","program":"refer-a-friend-two"}]'
            )
            .addPattern(
                '/v5/persons/p_me/rewards',
                200,
                '[{"id":"r1","face_value":5,"face_value_type":"USD","state":"FULFILLED","program":"refer-a-friend",' +
                    '"earned_date":"2026-11-18","journey_key":{"name":"identity_person_id","value":"p_me"}},' +
                    '{"id":"r2","face_value":20,"face_value_type":"USD","state":"SENT","program":"simple-offer-test",' +
                    '"earned_date":"2026-11-19"}]'
            )
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_me"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'member@example.com'
        );
        Test.stopTest();

        System.assertEquals(2, result.referrers.size());
        System.assertEquals('p_adv1', result.referredBy.personId);
        Map<String, ExtolePersonCard.OwnProgram> byProgram = new Map<String, ExtolePersonCard.OwnProgram>();
        for (ExtolePersonCard.OwnProgram op : result.ownPrograms)
            byProgram.put(op.program, op);
        // The offer is not a referral, so it is on the offers card instead.
        System.assertEquals(2, byProgram.size());
        System.assertEquals('rewarded', byProgram.get('refer-a-friend').status);
        System.assertEquals(
            '$5',
            byProgram.get('refer-a-friend').reward.amountLabel
        );
        // Referred in a second program with nothing decided yet.
        System.assertEquals(
            'pending',
            byProgram.get('refer-a-friend-two').status
        );

        ExtolePersonCard.OffersData offers = ExtolePersonCardController.getOffersData(
            'member@example.com'
        );
        System.assertEquals(1, offers.programs.size());
        System.assertEquals('simple-offer-test', offers.programs[0].program);
        System.assertEquals('$20', offers.programs[0].reward.amountLabel);
    }

    @IsTest
    static void testManyReferrersAreAllListedWithTheirEmail() {
        String rels = '[';
        for (Integer i = 0; i < 7; i++) {
            rels +=
                (i > 0 ? ',' : '') +
                '{"my_role":"FRIEND","other_person_id":"p_r' +
                i +
                '","program":"refer-a-friend","other_person":{"id":"p_r' +
                i +
                '","identity_key":"email","identity_key_value":"r' +
                i +
                '@example.com"}}';
        }
        rels += ']';
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern('/v5/persons/p_me/relationships', 200, rels)
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_me"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'member@example.com'
        );
        Test.stopTest();

        System.assertEquals(7, result.referrers.size());
        // Those past the first batch are never looked up, so they show the
        // email already on the relationship.
        System.assertEquals('r6@example.com', result.referrers[6].email);
        System.assertEquals('r6@example.com', result.referrers[6].displayName);
    }

    private static ExtoleConfigurableMock amountsMock(String components) {
        return new ExtoleConfigurableMock()
            .addPattern(
                '/v5/persons/p_me/relationships',
                200,
                '[{"my_role":"ADVOCATE","other_person_id":"p_f","program":"referral-program"}]'
            )
            .addPattern(
                '/v6/reward-suppliers',
                200,
                '[{"id":"s1","face_value":5,"face_value_type":"USD"},' +
                '{"id":"s2","face_value":10,"face_value_type":"USD"}]'
            )
            .addPattern(
                '/v2/campaign-summaries',
                200,
                '[{"campaign_id":"c1","program_label":"referral-program","state":"LIVE"}]'
            )
            .addPattern('/v2/campaigns/c1/components', 200, components)
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_me"}]'
            )
            .withDefault(200, '[]');
    }

    @IsTest
    static void testProgramAmountsSeparateTheAdvocateAndOwnReward() {
        Test.setMock(
            HttpCalloutMock.class,
            amountsMock(
                '[{"name":"advocate_reward","types":["reward-v10.0"],' +
                    '"variables":[{"name":"rewardSupplierId","values":{"default":"s2"}}]},' +
                    '{"name":"friend_reward","types":["reward-v10.0"],' +
                    '"variables":[{"name":"rewardSupplierId","values":{"default":"s1"}}]}]'
            )
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(
            '$10',
            result.advocateAmounts.get('referral-program')
        );
        System.assertEquals('$5', result.ownAmounts.get('referral-program'));
    }

    @IsTest
    static void testASingleUnnamedRewardIsTheOwnRewardNotTheAdvocates() {
        Test.setMock(
            HttpCalloutMock.class,
            amountsMock(
                '[{"name":"reward","types":["reward-v10.0"],' +
                '"variables":[{"name":"rewardSupplierId","values":{"default":"s1"}}]}]'
            )
        );

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        // It isn't clear who it pays, so it is never shown against the advocate.
        System.assertEquals(
            null,
            result.advocateAmounts.get('referral-program')
        );
        System.assertEquals('$5', result.ownAmounts.get('referral-program'));
        // It can stand in for a declined friend whose own amount is unknown.
        System.assertEquals('$5', result.onlyAmounts.get('referral-program'));
    }

    @IsTest
    static void testAdvocateDoesNotGetOwnSteps() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(
                '/v5/persons/p_me/relationships',
                200,
                '[{"my_role":"ADVOCATE","other_person_id":"p_f","program":"referral-program"}]'
            )
            .addPattern(
                '/v5/persons/p_me/steps?limit=25',
                200,
                '[{"name":"friend_signup","label":"Signed Up","event_date":"2026-01-02"}]'
            )
            .addPattern(
                '/v5/persons?identity_key_value=',
                200,
                '[{"id":"p_me"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(0, result.ownPrograms.size());
    }

    @IsTest
    static void testGetFriendDetailsReturnsRequestedFriendsInOrder() {
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
                '/v5/persons/p_friend/steps',
                200,
                '[{"name":"friend_signup","label":"Signed Up","event_date":"2026-01-02"}]'
            )
            .addPattern(
                '/v5/persons/p_friend',
                200,
                '{"id":"p_friend","identity_key":"email","identity_key_value":"friend@example.com"}'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<ExtolePersonCard.Friend> friends = ExtolePersonCardController.getFriendDetails(
            new List<String>{ 'p_friend' },
            new List<String>{ 'referral-program' },
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(1, friends.size());
        System.assertEquals('p_friend', friends[0].personId);
        System.assertEquals('friend@example.com', friends[0].email);
        System.assertEquals('Fiona Friend', friends[0].displayName);
        System.assertEquals('referral-program', friends[0].program);
        System.assertEquals(matchingFriend.Id, friends[0].sfdcRecordId);
    }

    @IsTest
    static void testGetFriendDetailsEmptyInput() {
        System.assertEquals(
            0,
            ExtolePersonCardController.getFriendDetails(
                    new List<String>(),
                    new List<String>(),
                    null,
                    null
                )
                .size()
        );
        System.assertEquals(
            0,
            ExtolePersonCardController.getFriendDetails(null, null, null, null)
                .size()
        );
    }

    @IsTest
    static void testRelationshipRequestExcludesAnonymousAndPages() {
        RecordingMock mock = new RecordingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCardController.getCardData('advocate@example.com');
        Test.stopTest();

        Boolean sawRelationships = false;
        for (String url : mock.urls) {
            if (url.contains('/relationships')) {
                sawRelationships = true;
                System.assert(url.contains('exclude_anonymous=true'), url);
                System.assert(url.contains('limit=100'), url);
                System.assert(url.contains('offset=0'), url);
            }
        }
        System.assertEquals(true, sawRelationships);
    }

    private class RecordingMock implements HttpCalloutMock {
        public List<String> urls = new List<String>();
        public String lookupBody = '[{"id":"p_advocate","identity_key":"email"}]';
        public String relationshipsBody = '[]';
        public HttpResponse respond(HttpRequest req) {
            urls.add(req.getEndpoint());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String url = req.getEndpoint();
            if (url.contains('/v5/persons?identity_key_value=')) {
                res.setBody(lookupBody);
            } else if (url.contains('/relationships')) {
                res.setBody(relationshipsBody);
            } else {
                res.setBody('[]');
            }
            return res;
        }
    }

    // ── Stress, limit and identity-key tests ──────────────────────────────────

    private static final String EMAIL_ADVOCATE = '[{"id":"p_advocate","identity_key":"email"}]';

    private static String relBody(Integer fromIndex, Integer count) {
        String body = '[';
        for (Integer i = fromIndex; i < fromIndex + count; i++) {
            body +=
                (i > fromIndex ? ',' : '') +
                '{"my_role":"ADVOCATE","other_person_id":"p_f' +
                i +
                '","program":"referral-program","other_person":{"id":"p_f' +
                i +
                '","identity_key":"email","identity_key_value":"f' +
                i +
                '@example.com"}}';
        }
        return body + ']';
    }

    private static String rewardBody(Integer fromIndex, Integer count) {
        String body = '[';
        for (Integer i = fromIndex; i < fromIndex + count; i++) {
            body +=
                (i > fromIndex ? ',' : '') +
                '{"reward_id":"r' +
                i +
                '","state":"EARNED","face_value":50,"face_value_type":"usd",' +
                '"date_earned":"2026-01-01","data":{"other_person_id":"p_f' +
                i +
                '"}}';
        }
        return body + ']';
    }

    @IsTest
    static void testRelationshipsPageAcrossMultipleRequests() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern('limit=100&offset=0', 200, relBody(0, 100))
            .addPattern('limit=100&offset=100', 200, relBody(100, 100))
            .addPattern('limit=100&offset=200', 200, relBody(200, 50))
            .addPattern('/v5/persons?identity_key_value=', 200, EMAIL_ADVOCATE)
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(250, result.totalFriends);
        System.assertEquals(250, result.friendRefs.size());
        System.assertEquals('p_f0', result.friendRefs[0].personId);
        System.assertEquals('p_f249', result.friendRefs[249].personId);
        System.assertEquals(
            'f249@example.com',
            result.friendRefs[249].identityValue
        );
        System.assertEquals(
            ExtolePersonCardController.FRIEND_BATCH,
            result.friends.size()
        );
    }

    @IsTest
    static void testRewardsPageAcrossMultipleRequests() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(
                '/relationships?exclude_anonymous=true&limit=100&offset=0',
                200,
                relBody(0, 100)
            )
            .addPattern(
                '/relationships?exclude_anonymous=true&limit=100&offset=100',
                200,
                relBody(100, 100)
            )
            .addPattern(
                '/relationships?exclude_anonymous=true&limit=100&offset=200',
                200,
                '[]'
            )
            .addPattern('/rewards?limit=100&offset=0', 200, rewardBody(0, 100))
            .addPattern(
                '/rewards?limit=100&offset=100',
                200,
                rewardBody(150, 1)
            )
            .addPattern('/v5/persons?identity_key_value=', 200, EMAIL_ADVOCATE)
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(200, result.friendRefs.size());
        System.assertNotEquals(
            null,
            result.friendRefs[99].reward,
            'first page'
        );
        System.assertNotEquals(
            null,
            result.friendRefs[150].reward,
            'second page'
        );
        System.assertEquals(null, result.friendRefs[120].reward);
    }

    @IsTest
    static void testRunawayPagingIsCappedAndDeduplicated() {
        RecordingMock mock = new RecordingMock();
        mock.relationshipsBody = relBody(0, 100);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        Integer relationshipCalls = 0;
        for (String url : mock.urls) {
            if (url.contains('/relationships'))
                relationshipCalls++;
        }
        System.assertEquals(
            10,
            relationshipCalls,
            'paging stops at the page cap'
        );
        System.assertEquals(100, result.totalFriends, 'repeats counted once');
    }

    @IsTest
    static void testPagingErrorKeepsFriendsAlreadyFetched() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern('limit=100&offset=0', 200, relBody(0, 100))
            .addPattern('limit=100&offset=100', 500, '{"error":"boom"}')
            .addPattern('/v5/persons?identity_key_value=', 200, EMAIL_ADVOCATE)
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(100, result.totalFriends);
        System.assertEquals(true, result.hasAnyData);
    }

    @IsTest
    static void testGetFriendDetailsStopsBeforeTheCalloutLimit() {
        // No identity values passed, so each friend needs 3 callouts: 33 fit in 100.
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(
                '/data',
                200,
                '{"email":{"name":"email","value":"f@example.com","scope":"PUBLIC"}}'
            )
            .addPattern('/steps', 200, '[]')
            .addPattern(
                '/v5/persons/',
                200,
                '{"id":"x","identity_key_value":"f@example.com"}'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        List<String> ids = new List<String>();
        for (Integer i = 0; i < 60; i++)
            ids.add('p_f' + i);

        Test.startTest();
        List<ExtolePersonCard.Friend> friends = ExtolePersonCardController.getFriendDetails(
            ids,
            null,
            null,
            null
        );
        Integer used = Limits.getCallouts();
        Test.stopTest();

        System.assertEquals(33, friends.size());
        System.assertEquals(99, used);
        System.assertEquals('p_f0', friends[0].personId);
        System.assertEquals('p_f32', friends[32].personId);
    }

    @IsTest
    static void testKnownIdentitySkipsTheProfileCalloutAndFitsMoreFriends() {
        // With the identity already known each friend needs only data and steps: 50 fit.
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern('/data', 200, '{}')
            .addPattern('/steps', 200, '[]')
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        List<String> ids = new List<String>();
        List<String> keys = new List<String>();
        List<String> values = new List<String>();
        for (Integer i = 0; i < 60; i++) {
            ids.add('p_f' + i);
            keys.add('email');
            values.add('f' + i + '@example.com');
        }

        Test.startTest();
        List<ExtolePersonCard.Friend> friends = ExtolePersonCardController.getFriendDetails(
            ids,
            null,
            keys,
            values
        );
        Integer used = Limits.getCallouts();
        Test.stopTest();

        System.assertEquals(50, friends.size());
        System.assertEquals(100, used);
        System.assertEquals(
            'f0@example.com',
            friends[0].email,
            'email comes from the identity when the data has none'
        );
    }

    @IsTest
    static void testNonEmailIdentityKeepsValueAsLabelAndNoEmail() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern('/data', 200, '{}')
            .addPattern('/steps', 200, '[]')
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<ExtolePersonCard.Friend> friends = ExtolePersonCardController.getFriendDetails(
            new List<String>{ 'p_a' },
            new List<String>{ 'x' },
            new List<String>{ 'member_number' },
            new List<String>{ 'M-1001' }
        );
        Test.stopTest();

        System.assertEquals(1, friends.size());
        System.assertEquals(
            null,
            friends[0].email,
            'a member number is not an email'
        );
        System.assertEquals('M-1001', friends[0].identityValue);
    }

    @IsTest
    static void testNonEmailAdvocateIsFoundByEmailFallback() {
        // The identity-key lookup finds nobody, so the card falls back to the email search.
        RecordingMock mock = new RecordingMock();
        mock.lookupBody = '[]';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCardController.getCardData('advocate@example.com');
        Test.stopTest();

        Boolean sawFallback = false;
        for (String url : mock.urls) {
            if (url.contains('/v2/persons?email='))
                sawFallback = true;
        }
        System.assertEquals(
            true,
            sawFallback,
            'falls back to the email search'
        );
    }

    @IsTest
    static void testNonEmailKeyedAdvocateDoesNotExcludeAnonymous() {
        RecordingMock mock = new RecordingMock();
        mock.lookupBody = '[{"id":"p_advocate","identity_key":"member_number"}]';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCardController.getCardData('advocate@example.com');
        Test.stopTest();

        Boolean saw = false;
        for (String url : mock.urls) {
            if (url.contains('/relationships')) {
                saw = true;
                System.assert(!url.contains('exclude_anonymous'), url);
            }
        }
        System.assertEquals(true, saw);
    }

    @IsTest
    static void testMultipleProgramsKeepEachFriendsProgram() {
        String rels =
            '[{"my_role":"ADVOCATE","other_person_id":"p_a","program":"refer-a-friend","other_person":{"identity_key":"email","identity_key_value":"a@example.com"}},' +
            '{"my_role":"ADVOCATE","other_person_id":"p_b","program":"member-get-member","other_person":{"identity_key":"email","identity_key_value":"b@example.com"}},' +
            '{"my_role":"ADVOCATE","other_person_id":"p_a","program":"member-get-member","other_person":{"identity_key":"email","identity_key_value":"a@example.com"}}]';
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern('/relationships', 200, rels)
            .addPattern('/v5/persons?identity_key_value=', 200, EMAIL_ADVOCATE)
            .addPattern('/data', 200, '{}')
            .addPattern('/steps', 200, '[]')
            .addPattern(
                '/v2/campaign-summaries',
                200,
                '[{"program_label":"refer-a-friend","campaign_id":"c1","state":"LIVE"},' +
                '{"program_label":"member-get-member","campaign_id":"c2","state":"LIVE"}]'
            )
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'advocate@example.com'
        );
        Test.stopTest();

        System.assertEquals(
            2,
            result.totalFriends,
            'a friend in two programs is listed once'
        );
        System.assertEquals('refer-a-friend', result.friendRefs[0].program);
        System.assertEquals('member-get-member', result.friendRefs[1].program);
    }

    @IsTest
    static void testGetFriendDetailsToleratesMismatchedAndNullLists() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, '[]')
        );

        Test.startTest();
        List<ExtolePersonCard.Friend> shortLists = ExtolePersonCardController.getFriendDetails(
            new List<String>{ 'p_a', 'p_b', 'p_c' },
            new List<String>{ 'only-one' },
            new List<String>{ 'email' },
            new List<String>{ 'a@example.com' }
        );
        List<ExtolePersonCard.Friend> nullElements = ExtolePersonCardController.getFriendDetails(
            new List<String>{ 'p_a', 'p_b' },
            new List<String>{ null, null },
            new List<String>{ null, null },
            new List<String>{ null, null }
        );
        Test.stopTest();

        System.assertEquals(3, shortLists.size());
        System.assertEquals('only-one', shortLists[0].program);
        System.assertEquals(null, shortLists[1].program);
        System.assertEquals(2, nullElements.size());
    }

    @IsTest
    static void testGetFriendDetailsWithDuplicateIdsDoesNotFail() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, '[]')
        );

        Test.startTest();
        List<ExtolePersonCard.Friend> friends = ExtolePersonCardController.getFriendDetails(
            new List<String>{ 'p_a', 'p_a', 'p_a' },
            new List<String>{ 'x', 'x', 'x' },
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(3, friends.size());
    }

    @IsTest
    static void testGetFriendDetailsSwallowsServerErrors() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(500, '{"error":"boom"}')
        );

        Test.startTest();
        List<ExtolePersonCard.Friend> friends = ExtolePersonCardController.getFriendDetails(
            new List<String>{ 'p_a', 'p_b' },
            new List<String>{ 'x', 'x' },
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(2, friends.size(), 'still listed, without details');
        System.assertEquals(null, friends[0].email);
    }

    @IsTest
    static void testReferrerOnlyShape() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .addPattern(
                '/relationships',
                200,
                '[{"my_role":"FRIEND","other_person_id":"p_referrer","program":"referral-program",' +
                '"other_person":{"identity_key":"member_number","identity_key_value":"M-7"}}]'
            )
            .addPattern('/v5/persons?identity_key_value=', 200, EMAIL_ADVOCATE)
            .withDefault(200, '[]');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtolePersonCard.CardData result = ExtolePersonCardController.getCardData(
            'referred@example.com'
        );
        Test.stopTest();

        System.assertEquals(0, result.totalFriends);
        System.assertNotEquals(null, result.referredBy);
        System.assertEquals(
            'M-7',
            result.referredBy.displayName,
            'falls back to the identity value'
        );
        System.assertEquals(true, result.hasAnyData);
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
}
