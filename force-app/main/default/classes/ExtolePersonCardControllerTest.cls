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
                '/v2/campaigns/c1/controllers',
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

        System.assertNotEquals(null, result.referredBy);
        System.assertEquals('p_referrer', result.referredBy.personId);
        System.assertEquals('referrer@example.com', result.referredBy.email);
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
}
