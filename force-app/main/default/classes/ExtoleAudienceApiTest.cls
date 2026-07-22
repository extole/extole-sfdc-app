@IsTest
private class ExtoleAudienceApiTest {
    private static ExtoleConfig config() {
        return new ExtoleConfig('https://api.extole.io', 'test-token');
    }

    private static final String AUDIENCE_JSON = '{"id":"aud_1","name":"Test Audience","enabled":true,"tags":["source:sfdc"],"component_ids":["c1"]}';

    // ── ExtoleAudience / list / get / create ─────────────────────────────────

    @IsTest
    static void testListAudiences_returnsParsedAudiencesAndFindsByName() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(200, '[' + AUDIENCE_JSON + ']')
        );

        Test.startTest();
        HttpResponse raw = new ExtoleClient()
            .send(config(), new ExtoleListAudiencesRequest().build(config()));
        ExtoleListAudiencesResponse resp = ExtoleListAudiencesResponse.fromResponse(
            raw
        );
        Test.stopTest();

        System.assertEquals(1, resp.audiences.size());
        ExtoleAudience found = resp.findByName('Test Audience');
        System.assertNotEquals(null, found);
        System.assertEquals('aud_1', found.audienceId);
        System.assertEquals(true, found.enabled);
        System.assertEquals(1, found.tags.size());
        System.assertEquals(1, found.componentIds.size());
        System.assertEquals(null, resp.findByName('Nonexistent'));
    }

    @IsTest
    static void testGetAudience_returnsParsedAudience() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, AUDIENCE_JSON)
        );

        Test.startTest();
        HttpResponse raw = new ExtoleClient()
            .send(
                config(),
                new ExtoleGetAudienceRequest('aud_1').build(config())
            );
        ExtoleGetAudienceResponse resp = ExtoleGetAudienceResponse.fromResponse(
            raw
        );
        Test.stopTest();

        System.assertEquals('aud_1', resp.audience.audienceId);
        System.assertEquals('Test Audience', resp.audience.name);
    }

    @IsTest
    static void testGetAudience_blankIdThrows() {
        Boolean threw = false;
        try {
            new ExtoleGetAudienceRequest('').build(config());
        } catch (ExtoleApiException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetAudience_errorStatusThrows() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(404, '{"error":"not_found"}')
        );
        Boolean threw = false;
        Test.startTest();
        try {
            HttpResponse raw = new ExtoleClient()
                .send(
                    config(),
                    new ExtoleGetAudienceRequest('missing').build(config())
                );
            ExtoleGetAudienceResponse.fromResponse(raw);
        } catch (ExtoleApiException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testCreateAudience_buildsExpectedBodyAndParsesResponse() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(201, AUDIENCE_JSON)
        );

        Test.startTest();
        HttpRequest req = new ExtoleCreateAudienceRequest('Test Audience')
            .withEnabled(false)
            .withTags(new List<String>{ 'source:sfdc' })
            .build(config());
        HttpResponse raw = new ExtoleClient().send(config(), req);
        ExtoleCreateAudienceResponse resp = ExtoleCreateAudienceResponse.fromResponse(
            raw
        );
        Test.stopTest();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
            req.getBody()
        );
        System.assertEquals('Test Audience', body.get('name'));
        System.assertEquals(false, body.get('enabled'));
        System.assertEquals('aud_1', resp.audience.audienceId);
    }

    @IsTest
    static void testCreateAudience_blankNameThrows() {
        Boolean threw = false;
        try {
            new ExtoleCreateAudienceRequest('').build(config());
        } catch (ExtoleApiException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    // ── ExtoleAudienceOperation (submit + poll state) ────────────────────────

    @IsTest
    static void testOperationRequest_buildsPersonListBodyWithEmails() {
        Test.startTest();
        HttpRequest req = new ExtoleAudienceOperationRequest(
                'aud_1',
                ExtoleAudienceOperationRequest.TYPE_REPLACE
            )
            .withEmails(
                new List<String>{ 'a@example.com', '', 'b@example.com' }
            )
            .withTags(new List<String>{ 'source:sfdc' })
            .build(config());
        Test.stopTest();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
            req.getBody()
        );
        System.assertEquals('REPLACE', body.get('type'));
        Map<String, Object> dataSource = (Map<String, Object>) body.get(
            'data_source'
        );
        List<Object> members = (List<Object>) dataSource.get(
            'audience_members'
        );
        // Blank email is skipped.
        System.assertEquals(2, members.size());
    }

    @IsTest
    static void testOperationRequest_invalidTypeThrows() {
        Boolean threw = false;
        try {
            new ExtoleAudienceOperationRequest('aud_1', 'BOGUS')
                .build(config());
        } catch (ExtoleApiException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testOperationRequest_blankAudienceIdThrows() {
        Boolean threw = false;
        try {
            new ExtoleAudienceOperationRequest(
                    '',
                    ExtoleAudienceOperationRequest.TYPE_ADD
                )
                .build(config());
        } catch (ExtoleApiException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testOperationResponse_parsesSubmittedOperation() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(
                    200,
                    '{"id":"op_1","audience_id":"aud_1","type":"REPLACE"}'
                )
        );

        Test.startTest();
        HttpRequest req = new ExtoleAudienceOperationRequest(
                'aud_1',
                ExtoleAudienceOperationRequest.TYPE_REPLACE
            )
            .withEmails(new List<String>{ 'a@example.com' })
            .build(config());
        HttpResponse raw = new ExtoleClient().send(config(), req);
        ExtoleAudienceOperationResponse resp = ExtoleAudienceOperationResponse.fromResponse(
            raw
        );
        Test.stopTest();

        System.assertEquals('op_1', resp.operation.operationId);
        System.assertEquals('aud_1', resp.operation.audienceId);
    }

    @IsTest
    static void testOperationStateRequest_blankIdsThrow() {
        Boolean threwAudience = false;
        try {
            new ExtoleAudienceOperationStateRequest('', 'op_1').build(config());
        } catch (ExtoleApiException e) {
            threwAudience = true;
        }
        System.assertEquals(true, threwAudience);

        Boolean threwOperation = false;
        try {
            new ExtoleAudienceOperationStateRequest('aud_1', '')
                .build(config());
        } catch (ExtoleApiException e) {
            threwOperation = true;
        }
        System.assertEquals(true, threwOperation);
    }

    @IsTest
    static void testOperationStateResponse_readyIsTerminalAndSuccess() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(
                    200,
                    '{"id":"op_1","audience_id":"aud_1","status":"READY"}'
                )
        );

        Test.startTest();
        HttpRequest req = new ExtoleAudienceOperationStateRequest(
                'aud_1',
                'op_1'
            )
            .build(config());
        HttpResponse raw = new ExtoleClient().send(config(), req);
        ExtoleAudienceOperationStateResponse resp = ExtoleAudienceOperationStateResponse.fromResponse(
            raw
        );
        Test.stopTest();

        // state falls back to top-level "status" when "state" is absent.
        System.assertEquals('READY', resp.operation.state);
        System.assertEquals(true, resp.isTerminal());
        System.assertEquals(true, resp.isSuccess());
    }

    @IsTest
    static void testOperationStateResponse_failedIsTerminalNotSuccess() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(
                    200,
                    '{"id":"op_1","audience_id":"aud_1","state":"FAILED"}'
                )
        );

        Test.startTest();
        HttpRequest req = new ExtoleAudienceOperationStateRequest(
                'aud_1',
                'op_1'
            )
            .build(config());
        HttpResponse raw = new ExtoleClient().send(config(), req);
        ExtoleAudienceOperationStateResponse resp = ExtoleAudienceOperationStateResponse.fromResponse(
            raw
        );
        Test.stopTest();

        System.assertEquals(true, resp.isTerminal());
        System.assertEquals(false, resp.isSuccess());
    }

    @IsTest
    static void testOperationStateResponse_preparingIsNotTerminal() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(
                    200,
                    '{"id":"op_1","audience_id":"aud_1","state":"PREPARING"}'
                )
        );

        Test.startTest();
        HttpRequest req = new ExtoleAudienceOperationStateRequest(
                'aud_1',
                'op_1'
            )
            .build(config());
        HttpResponse raw = new ExtoleClient().send(config(), req);
        ExtoleAudienceOperationStateResponse resp = ExtoleAudienceOperationStateResponse.fromResponse(
            raw
        );
        Test.stopTest();

        System.assertEquals(false, resp.isTerminal());
        System.assertEquals(false, resp.isSuccess());
    }
}
