@IsTest
private class ExtoleRewardsApiTest {

    private static ExtoleConfig config() {
        return new ExtoleConfig('https://api.extole.io', 'test-token');
    }

    @IsTest
    static void getRewards_happyPath() {
        String body = '[' +
            '{"id":"r_1","face_value":15,"face_value_type":"PERCENT_OFF",' +
            '"earned_date":"2026-03-01T00:00:00Z","state":"SENT",' +
            '"program":"refer-a-friend","partner_reward_id":"ABC123",' +
            '"tags":["ADVOCATE_ANY_SEARCH"],' +
            '"created_date":"2026-03-01T00:00:00Z","redeemed_date":null,"expiry_date":null,' +
            '"journey_name":"ADVOCATE","reward_supplier_name":"Credit"},' +
            '{"id":"r_2","face_value":10,"face_value_type":"PERCENT_OFF",' +
            '"earned_date":"2026-04-01T00:00:00Z","state":"REDEEMED",' +
            '"program":"refer-a-friend","partner_reward_id":"XYZ789",' +
            '"tags":[],' +
            '"created_date":"2026-04-01T00:00:00Z","redeemed_date":"2026-04-02T00:00:00Z","expiry_date":null,' +
            '"journey_name":"ADVOCATE","reward_supplier_name":"Credit"}' +
            ']';
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, body));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleGetRewardsRequest('p_abc').build(config()));
        ExtoleGetRewardsResponse resp = ExtoleGetRewardsResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(2, resp.rewards.size());

        ExtoleReward r1 = resp.rewards[0];
        System.assertEquals('r_1', r1.rewardId);
        System.assertEquals('15', r1.faceValue);
        System.assertEquals('PERCENT_OFF', r1.faceValueType);
        System.assertEquals('2026-03-01T00:00:00Z', r1.dateEarned);
        System.assertEquals('SENT', r1.state);
        System.assertEquals('refer-a-friend', r1.program);
        System.assertEquals('ABC123', r1.partnerRewardId);
        System.assertEquals(1, r1.tags.size());
        System.assertEquals('ADVOCATE_ANY_SEARCH', r1.tags[0]);
        System.assertEquals('2026-03-01T00:00:00Z', r1.createdDate);
        System.assertEquals(null, r1.redeemedDate);
        System.assertEquals(null, r1.expiryDate);
        System.assertEquals('ADVOCATE', r1.journeyName);
        System.assertEquals('Credit', r1.rewardSupplierName);

        ExtoleReward r2 = resp.rewards[1];
        System.assertEquals('r_2', r2.rewardId);
        System.assertEquals('REDEEMED', r2.state);
        System.assertEquals('2026-04-02T00:00:00Z', r2.redeemedDate);
        System.assertEquals(0, r2.tags.size());
    }

    @IsTest
    static void getRewards_emptyList_returnsEmpty() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, '[]'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleGetRewardsRequest('p_abc').build(config()));
        ExtoleGetRewardsResponse resp = ExtoleGetRewardsResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(0, resp.rewards.size());
    }

    @IsTest
    static void getRewards_404_throwsApiException() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(404, '{"error":"not_found"}'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleGetRewardsRequest('p_missing').build(config()));
        Test.stopTest();

        try {
            ExtoleGetRewardsResponse.fromResponse(raw);
            System.assert(false, 'Expected ExtoleApiException');
        } catch (ExtoleApiException e) {
            System.assertEquals(404, e.httpStatus);
        }
    }

    @IsTest
    static void getRewards_missingPersonId_throwsIllegalArgument() {
        try {
            new ExtoleGetRewardsRequest('').build(config());
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('personId'));
        }
    }

    @IsTest
    static void getRewards_endpointContainsPersonIdAndRewardsPath() {
        HttpRequest req = new ExtoleGetRewardsRequest('p_abc').build(config());
        System.assert(req.getEndpoint().contains('p_abc'));
        System.assert(req.getEndpoint().contains('/rewards'));
    }
}
