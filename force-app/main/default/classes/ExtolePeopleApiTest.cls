@IsTest
private class ExtolePeopleApiTest {

    private static ExtoleConfig config() {
        return new ExtoleConfig('https://api.extole.io', 'test-token');
    }

    // Main person response — only id and identity_key_value (email) are present
    private static final String PERSON_JSON =
        '{"id":"p_abc","identity_key":"email","identity_key_value":"jane@example.com",' +
        '"identity_id":"p_abc","version":"5:5"}';

    // /data endpoint response — keyed attribute objects with a value field
    private static final String DATA_JSON =
        '{"first_name":{"name":"first_name","value":"Jane","scope":"PUBLIC"},' +
        '"last_name":{"name":"last_name","value":"Smith","scope":"PRIVATE"},' +
        '"partner_user_id":{"name":"partner_user_id","value":"001xx1","scope":"PRIVATE"},' +
        '"share_link":{"name":"share_link","value":"https://refer.example.com/jane","scope":"PUBLIC"}}';

    @IsTest
    static void lookupByEmail_returnsPerson() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, '[' + PERSON_JSON + ']'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            ExtoleGetPersonRequest.byEmail('jane@example.com').build(config()));
        ExtoleGetPersonResponse resp = ExtoleGetPersonResponse.fromResponse(raw);
        Test.stopTest();

        System.assertNotEquals(null, resp.person);
        System.assertEquals('p_abc', resp.person.id);
        System.assertEquals('jane@example.com', resp.person.email);
    }

    @IsTest
    static void applyData_populatesProfileFields() {
        ExtolePerson p = ExtolePerson.fromMap(
            (Map<String, Object>) JSON.deserializeUntyped(PERSON_JSON));
        Map<String, Object> dataMap =
            (Map<String, Object>) JSON.deserializeUntyped(DATA_JSON);
        p.applyData(dataMap);

        System.assertEquals('Jane', p.firstName);
        System.assertEquals('Smith', p.lastName);
        System.assertEquals('001xx1', p.partnerUserId);
        System.assertEquals('https://refer.example.com/jane', p.shareLink);
    }

    @IsTest
    static void applyData_missingField_remainsNull() {
        ExtolePerson p = ExtolePerson.fromMap(
            (Map<String, Object>) JSON.deserializeUntyped(PERSON_JSON));
        p.applyData(new Map<String, Object>());

        System.assertEquals(null, p.firstName);
        System.assertEquals(null, p.lastName);
    }

    @IsTest
    static void lookupByEmail_notFound_returnsNullPerson() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, '[]'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            ExtoleGetPersonRequest.byEmail('nobody@example.com').build(config()));
        ExtoleGetPersonResponse resp = ExtoleGetPersonResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(null, resp.person);
    }

    @IsTest
    static void lookupById_returnsPerson() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, PERSON_JSON));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            ExtoleGetPersonRequest.byId('p_abc').build(config()));
        ExtoleGetPersonResponse resp = ExtoleGetPersonResponse.fromResponse(raw);
        Test.stopTest();

        System.assertNotEquals(null, resp.person);
        System.assertEquals('p_abc', resp.person.id);
    }

    @IsTest
    static void lookupById_404_throwsApiException() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(404, '{"error":"not_found"}'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            ExtoleGetPersonRequest.byId('p_missing').build(config()));
        Test.stopTest();

        try {
            ExtoleGetPersonResponse.fromResponse(raw);
            System.assert(false, 'Expected ExtoleApiException');
        } catch (ExtoleApiException e) {
            System.assertEquals(404, e.httpStatus);
        }
    }

    @IsTest
    static void lookupByEmail_endpointContainsIdentityKeyValue() {
        HttpRequest req = ExtoleGetPersonRequest.byEmail('jane@example.com').build(config());
        System.assert(req.getEndpoint().contains('identity_key_value'));
        System.assert(req.getEndpoint().contains('jane'));
    }

    @IsTest
    static void missingEmailAndId_throwsIllegalArgument() {
        try {
            ExtoleGetPersonRequest.byEmail('').build(config());
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(true);
        }
    }
}
