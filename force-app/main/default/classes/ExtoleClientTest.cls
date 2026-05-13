@IsTest
private class ExtoleClientTest {

    @IsTest
    static void namedCredentialConfig_returnsCalloutEndpoint() {
        ExtoleConfig config = new ExtoleConfig('Extole_API');
        System.assertEquals('callout:Extole_API', config.getEndpoint());
        System.assertEquals(null, config.getAuthHeader());
        System.assert(config.isNamedCredentialMode());
    }

    @IsTest
    static void directTokenConfig_returnsBaseUrlAndAuthHeader() {
        ExtoleConfig config = new ExtoleConfig('https://api.extole.io', 'my-token');
        System.assertEquals('https://api.extole.io', config.getEndpoint());
        System.assertEquals('Bearer my-token', config.getAuthHeader());
        System.assert(!config.isNamedCredentialMode());
    }

    @IsTest
    static void withTimeout_overridesDefault() {
        ExtoleConfig config = new ExtoleConfig('Extole_API').withTimeout(5000);
        System.assertEquals(5000, config.timeoutMs);
    }

    @IsTest
    static void send_propagatesCalloutResponse() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .withDefault(200, '{"id":"evt-1","status":"received"}');
        Test.setMock(HttpCalloutMock.class, mock);

        ExtoleConfig config = new ExtoleConfig('https://api.extole.io', 'tok');
        ExtoleEventFireRequest req = new ExtoleEventFireRequest('test_event')
            .withData('email', 'test@example.com');

        Test.startTest();
        HttpResponse res = new ExtoleClient().send(config, req.build(config));
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
    }

    @IsTest
    static void withAppType_appendsQueryParam() {
        // No existing query string — should append with '?'
        System.assertEquals(
            'https://api.extole.io/v5/persons?app_type=extole-sfdc-app',
            ExtoleClient.withAppType('https://api.extole.io/v5/persons')
        );
        // Existing query string — should append with '&'
        System.assertEquals(
            'https://api.extole.io/v5/persons?identity_key_value=a%40b.com&app_type=extole-sfdc-app',
            ExtoleClient.withAppType('https://api.extole.io/v5/persons?identity_key_value=a%40b.com')
        );
        // Already has app_type — should not double up
        System.assertEquals(
            'https://api.extole.io/v5/persons?app_type=other',
            ExtoleClient.withAppType('https://api.extole.io/v5/persons?app_type=other')
        );
    }

    @IsTest
    static void fromResponse_401_throwsApiException() {
        ExtoleConfigurableMock mock = new ExtoleConfigurableMock()
            .withDefault(401, '{"error":"unauthorized"}');
        Test.setMock(HttpCalloutMock.class, mock);

        ExtoleConfig config = new ExtoleConfig('https://api.extole.io', 'bad-token');
        ExtoleEventFireRequest req = new ExtoleEventFireRequest('test_event');

        Test.startTest();
        HttpResponse res = new ExtoleClient().send(config, req.build(config));
        Test.stopTest();

        try {
            ExtoleEventFireResponse.fromResponse(res);
            System.assert(false, 'Expected ExtoleApiException');
        } catch (ExtoleApiException e) {
            System.assertEquals(401, e.httpStatus);
        }
    }
}
