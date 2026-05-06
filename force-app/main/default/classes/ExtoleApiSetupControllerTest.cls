@IsTest
private class ExtoleApiSetupControllerTest {

    @IsTest
    static void testConnection_success_returnsSuccessTrue() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, '[{"report_runner_id":"r1","name":"Test","description":""}]'));

        Test.startTest();
        Map<String, Object> result = ExtoleApiSetupController.testConnection();
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals('Connected successfully.', result.get('message'));
    }

    private class ThrowingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            CalloutException e = new CalloutException();
            e.setMessage('Network unreachable');
            throw e;
        }
    }

    @IsTest
    static void testConnection_calloutException_returnsSuccessFalse() {
        Test.setMock(HttpCalloutMock.class, new ThrowingMock());

        Test.startTest();
        Map<String, Object> result = ExtoleApiSetupController.testConnection();
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assert(((String) result.get('message')).contains('Network unreachable'));
    }

    @IsTest
    static void testConnection_401_returnsSuccessFalseWithStatus() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(401, '{"error":"unauthorized"}'));

        Test.startTest();
        Map<String, Object> result = ExtoleApiSetupController.testConnection();
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assert(((String) result.get('message')).contains('401'));
    }
}
