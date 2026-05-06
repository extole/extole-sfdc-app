@IsTest
private class ExtoleProgramsApiTest {

    private static ExtoleConfig config() {
        return new ExtoleConfig('https://api.extole.io', 'test-token');
    }

    // ── Programs (summary) ──────────────────────────────────────────────────

    @IsTest
    static void listPrograms_returnsPrograms() {
        String body = '[' +
            '{"campaign_id":101,"name":"Refer a Friend","state":"PUBLISHED","program_label":"raf"},' +
            '{"campaign_id":102,"name":"VIP Program","state":"ACTIVE","program_label":"vip"}' +
            ']';
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, body));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleListProgramsRequest().build(config()));
        ExtoleListProgramsResponse resp = ExtoleListProgramsResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(2, resp.programs.size());
        System.assertEquals('101', resp.programs[0].campaignId);
        System.assertEquals('Refer a Friend', resp.programs[0].name);
        System.assertEquals('PUBLISHED', resp.programs[0].state);
        System.assertEquals('raf', resp.programs[0].programLabel);
    }

    @IsTest
    static void listPrograms_emptyList_returnsEmpty() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, '[]'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleListProgramsRequest().build(config()));
        ExtoleListProgramsResponse resp = ExtoleListProgramsResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(0, resp.programs.size());
    }

    @IsTest
    static void listPrograms_nullCampaignId_returnsNullNotStringNull() {
        String body = '[{"name":"No ID Program","state":"DRAFT","program_label":"noid"}]';
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, body));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleListProgramsRequest().build(config()));
        ExtoleListProgramsResponse resp = ExtoleListProgramsResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(null, resp.programs[0].campaignId);
    }

    @IsTest
    static void listPrograms_4xx_throwsApiException() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(403, '{"error":"forbidden"}'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleListProgramsRequest().build(config()));
        Test.stopTest();

        try {
            ExtoleListProgramsResponse.fromResponse(raw);
            System.assert(false, 'Expected ExtoleApiException');
        } catch (ExtoleApiException e) {
            System.assertEquals(403, e.httpStatus);
        }
    }

    // ── Campaigns (full) ────────────────────────────────────────────────────

    @IsTest
    static void getCampaigns_returnsEventNames() {
        String body = '[{"campaign_id":101,"name":"Refer a Friend","state":"LIVE",' +
            '"steps":[{"triggers":[{"event_names":["close_won","opportunity_created"]}]}]}]';
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, body));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleGetCampaignsRequest().build(config()));
        ExtoleGetCampaignsResponse resp = ExtoleGetCampaignsResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(1, resp.campaigns.size());
        ExtoleCampaign c = resp.campaigns[0];
        System.assert(c.referencesEvent('close_won'));
        System.assert(c.referencesEvent('opportunity_created'));
        System.assert(!c.referencesEvent('unknown_event'));
    }

    @IsTest
    static void getCampaigns_noSteps_returnsEmptyEventNames() {
        String body = '[{"campaign_id":102,"name":"No Steps","state":"LIVE"}]';
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, body));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleGetCampaignsRequest().build(config()));
        ExtoleGetCampaignsResponse resp = ExtoleGetCampaignsResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(0, resp.campaigns[0].eventNames.size());
    }

    @IsTest
    static void getCampaigns_withStateOverride_endpointContainsState() {
        HttpRequest req = new ExtoleGetCampaignsRequest().withState('DRAFT').build(config());
        System.assert(req.getEndpoint().contains('DRAFT'));
    }

    @IsTest
    static void getCampaigns_4xx_throwsApiException() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(401, '{"error":"unauthorized"}'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleGetCampaignsRequest().build(config()));
        Test.stopTest();

        try {
            ExtoleGetCampaignsResponse.fromResponse(raw);
            System.assert(false, 'Expected ExtoleApiException');
        } catch (ExtoleApiException e) {
            System.assertEquals(401, e.httpStatus);
        }
    }

    @IsTest
    static void getCampaigns_nullCampaignId_returnsNullNotStringNull() {
        String body = '[{"name":"No ID","state":"LIVE"}]';
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, body));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleGetCampaignsRequest().build(config()));
        ExtoleGetCampaignsResponse resp = ExtoleGetCampaignsResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(null, resp.campaigns[0].campaignId);
    }
}
