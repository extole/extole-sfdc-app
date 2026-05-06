@IsTest
private class ExtoleEventApiTest {

    private static ExtoleConfig config() {
        return new ExtoleConfig('https://api.extole.io', 'test-token');
    }

    @IsTest
    static void fireEvent_happyPath() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, '{"id":"evt-abc"}'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleEventFireRequest('close_won')
                .withData('email', 'jane@example.com')
                .withData('partner_user_id', '001xx000003GYn1')
                .build(config()));
        ExtoleEventFireResponse resp = ExtoleEventFireResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals('evt-abc', resp.eventId);
    }

    @IsTest
    static void fireEvent_400_throwsApiException() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(400, '{"error":"invalid_event_name"}'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleEventFireRequest('bad event').build(config()));
        Test.stopTest();

        try {
            ExtoleEventFireResponse.fromResponse(raw);
            System.assert(false, 'Expected ExtoleApiException');
        } catch (ExtoleApiException e) {
            System.assertEquals(400, e.httpStatus);
        }
    }

    @IsTest
    static void fireEvent_401_throwsApiException() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(401, '{"error":"invalid_token"}'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleEventFireRequest('close_won').build(config()));
        Test.stopTest();

        try {
            ExtoleEventFireResponse.fromResponse(raw);
            System.assert(false, 'Expected ExtoleApiException');
        } catch (ExtoleApiException e) {
            System.assertEquals(401, e.httpStatus);
        }
    }

    @IsTest
    static void fireEvent_missingEventName_throwsIllegalArgument() {
        try {
            new ExtoleEventFireRequest('').build(config());
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('eventName'));
        }
    }

    @IsTest
    static void fireEvent_requestBodyContainsEventNameAndData() {
        HttpRequest req = new ExtoleEventFireRequest('close_won')
            .withData('email', 'test@test.com')
            .build(config());

        String body = req.getBody();
        System.assert(body.contains('close_won'));
        System.assert(body.contains('test@test.com'));
        System.assertEquals('POST', req.getMethod());
    }
}
