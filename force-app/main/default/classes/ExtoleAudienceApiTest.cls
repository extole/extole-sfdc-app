@IsTest
private class ExtoleAudienceApiTest {
    private static ExtoleConfig config() {
        return new ExtoleConfig('https://api.extole.io', 'test-token');
    }

    private static final String AUDIENCE_JSON = '{"id":"aud_1","name":"Test Audience","enabled":true,"tags":["source:sfdc"],"component_ids":["c1"]}';

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
        ExtoleListAudiencesResponse response = ExtoleListAudiencesResponse.fromResponse(
            raw
        );
        Test.stopTest();

        System.assertEquals(1, response.audiences.size());
        ExtoleAudience found = response.findByName('Test Audience');
        System.assertNotEquals(null, found);
        System.assertEquals('aud_1', found.audienceId);
        System.assertEquals(true, found.enabled);
        System.assertEquals(1, found.tags.size());
        System.assertEquals(1, found.componentIds.size());
        System.assertEquals(null, response.findByName('Nonexistent'));
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
        ExtoleGetAudienceResponse response = ExtoleGetAudienceResponse.fromResponse(
            raw
        );
        Test.stopTest();

        System.assertEquals('aud_1', response.audience.audienceId);
        System.assertEquals('Test Audience', response.audience.name);
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
        HttpRequest request = new ExtoleCreateAudienceRequest('Test Audience')
            .withEnabled(false)
            .withTags(new List<String>{ 'source:sfdc' })
            .build(config());
        HttpResponse raw = new ExtoleClient().send(config(), request);
        ExtoleCreateAudienceResponse response = ExtoleCreateAudienceResponse.fromResponse(
            raw
        );
        Test.stopTest();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
            request.getBody()
        );
        System.assertEquals('Test Audience', body.get('name'));
        System.assertEquals(false, body.get('enabled'));
        System.assertEquals('aud_1', response.audience.audienceId);
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

    @IsTest
    static void testOperationRequest_buildsPersonListBodyWithEmails() {
        Test.startTest();
        HttpRequest request = new ExtoleAudienceOperationRequest(
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
            request.getBody()
        );
        System.assertEquals('REPLACE', body.get('type'));
        Map<String, Object> dataSource = (Map<String, Object>) body.get(
            'data_source'
        );
        List<Object> members = (List<Object>) dataSource.get(
            'audience_members'
        );
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
        HttpRequest request = new ExtoleAudienceOperationRequest(
                'aud_1',
                ExtoleAudienceOperationRequest.TYPE_REPLACE
            )
            .withEmails(new List<String>{ 'a@example.com' })
            .build(config());
        HttpResponse raw = new ExtoleClient().send(config(), request);
        ExtoleAudienceOperationResponse response = ExtoleAudienceOperationResponse.fromResponse(
            raw
        );
        Test.stopTest();

        System.assertEquals('op_1', response.operation.operationId);
        System.assertEquals('aud_1', response.operation.audienceId);
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
        HttpRequest request = new ExtoleAudienceOperationStateRequest(
                'aud_1',
                'op_1'
            )
            .build(config());
        HttpResponse raw = new ExtoleClient().send(config(), request);
        ExtoleAudienceOperationStateResponse response = ExtoleAudienceOperationStateResponse.fromResponse(
            raw
        );
        Test.stopTest();

        System.assertEquals('READY', response.operation.state);
        System.assertEquals(true, response.isTerminal());
        System.assertEquals(true, response.isSuccess());
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
        HttpRequest request = new ExtoleAudienceOperationStateRequest(
                'aud_1',
                'op_1'
            )
            .build(config());
        HttpResponse raw = new ExtoleClient().send(config(), request);
        ExtoleAudienceOperationStateResponse response = ExtoleAudienceOperationStateResponse.fromResponse(
            raw
        );
        Test.stopTest();

        System.assertEquals(true, response.isTerminal());
        System.assertEquals(false, response.isSuccess());
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
        HttpRequest request = new ExtoleAudienceOperationStateRequest(
                'aud_1',
                'op_1'
            )
            .build(config());
        HttpResponse raw = new ExtoleClient().send(config(), request);
        ExtoleAudienceOperationStateResponse response = ExtoleAudienceOperationStateResponse.fromResponse(
            raw
        );
        Test.stopTest();

        System.assertEquals(false, response.isTerminal());
        System.assertEquals(false, response.isSuccess());
    }
}
