@IsTest
private class ExtoleWebhookControllerTest {
    // ── Helpers ────────────────────────────────────────────────────────────────

    private static void setRequest(String body) {
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf(body);
    }

    private static Extole_Writeback_Cfg__c makeConfig(
        String eventName,
        String objType,
        String mappingsJson
    ) {
        Extole_Writeback_Cfg__c cfg = new Extole_Writeback_Cfg__c();
        cfg.Name = 'Test Config';
        cfg.Event_Name__c = eventName;
        cfg.Object_Type__c = objType;
        cfg.Status__c = 'ACTIVE';
        cfg.Field_Mappings__c = mappingsJson;
        insert cfg;
        return cfg;
    }

    // ── Bad request tests ──────────────────────────────────────────────────────

    @IsTest
    static void testInvalidJson() {
        setRequest('not json at all');
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();
        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString()
                .contains('invalid_payload')
        );
    }

    @IsTest
    static void testMissingEventName() {
        setRequest('{"data":{"email":"test@example.com"}}');
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();
        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString()
                .contains('missing_event_name')
        );
    }

    // ── No-config path ─────────────────────────────────────────────────────────

    @IsTest
    static void testNoConfigSkipped() {
        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-001","data":{"email":"x@x.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();
        System.assertEquals(200, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('skipped')
        );
        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('SKIPPED', logs[0].Status__c);
    }

    @IsTest
    static void testInactiveConfigSkipped() {
        Extole_Writeback_Cfg__c cfg = makeConfig(
            'reward_earned',
            'Contact',
            null
        );
        cfg.Status__c = 'INACTIVE';
        update cfg;

        Contact c = new Contact(
            LastName = 'Test',
            Email = 'inactive-rule@example.com'
        );
        insert c;

        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-inactive-001","data":{"email":"inactive-rule@example.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('skipped')
        );
        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('SKIPPED', logs[0].Status__c);
    }

    // ── Duplicate event_id ─────────────────────────────────────────────────────

    @IsTest
    static void testDuplicateEventId() {
        // Seed a prior SUCCESS log for the same event_id
        Extole_Writeback_Log__c prior = new Extole_Writeback_Log__c(
            Event_Id__c = 'dup-123',
            Event_Name__c = 'reward_earned',
            Status__c = 'SUCCESS',
            Received_At__c = System.now()
        );
        insert prior;

        setRequest(
            '{"event_name":"reward_earned","event_id":"dup-123","data":{"email":"x@x.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();
        System.assertEquals(200, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('duplicate')
        );
        // Only the seeded log, no new one
        System.assertEquals(1, [SELECT COUNT() FROM Extole_Writeback_Log__c]);
    }

    // ── Contact update ─────────────────────────────────────────────────────────

    @IsTest
    static void testContactUpdateByEmail() {
        Contact c = new Contact(
            LastName = 'Tester',
            Email = 'tester@example.com'
        );
        insert c;
        makeConfig('reward_earned', 'Contact', null);

        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-c1","data":{"email":"tester@example.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString()
                .contains('"status":"ok"')
        );
        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c, Record_Id__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('SUCCESS', logs[0].Status__c);
        System.assertEquals(c.Id, logs[0].Record_Id__c);
    }

    @IsTest
    static void testContactUpdateBySalesforceId() {
        Contact c = new Contact(LastName = 'SfidTest');
        insert c;
        makeConfig('reward_earned', 'Contact', null);

        String payload =
            '{"event_name":"reward_earned","event_id":"ev-c2","data":{"salesforce_id":"' +
            c.Id +
            '"}}';
        setRequest(payload);
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c, Record_Id__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals('SUCCESS', logs[0].Status__c);
        System.assertEquals(c.Id, logs[0].Record_Id__c);
    }

    // ── Lead update ────────────────────────────────────────────────────────────

    @IsTest
    static void testLeadUpdateByEmail() {
        Lead l = new Lead(
            LastName = 'LeadTest',
            Company = 'ACME',
            Email = 'lead@example.com'
        );
        insert l;
        makeConfig('reward_earned', 'Lead', null);

        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-l1","data":{"email":"lead@example.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c, Record_Id__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals('SUCCESS', logs[0].Status__c);
        System.assertEquals(l.Id, logs[0].Record_Id__c);
    }

    // ── No matching record ─────────────────────────────────────────────────────

    @IsTest
    static void testNoRecordFound() {
        makeConfig('reward_earned', 'Contact', null);
        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-nr1","data":{"email":"nobody@nowhere.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('SKIPPED', logs[0].Status__c);
    }

    // ── Field mapping ──────────────────────────────────────────────────────────

    @IsTest
    static void testApplyMappings() {
        Contact c = new Contact(
            LastName = 'MapTest',
            Email = 'map@example.com'
        );
        insert c;
        // Map extole 'value' → SFDC Description (standard field, always writable)
        makeConfig(
            'reward_earned',
            'Contact',
            '[{"extoleKey":"value","sfdcField":"Description"}]'
        );

        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-m1","data":{"email":"map@example.com","value":"Gold"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        Contact updated = [SELECT Description FROM Contact WHERE Id = :c.Id];
        System.assertEquals('Gold', updated.Description);
        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals('SUCCESS', logs[0].Status__c);
    }

    @IsTest
    static void testApplyMappings_missingKey() {
        // Key not present in data → field should not be set but no error
        Contact c = new Contact(
            LastName = 'MapMiss',
            Email = 'miss@example.com'
        );
        insert c;
        makeConfig(
            'reward_earned',
            'Contact',
            '[{"extoleKey":"nonexistent_key","sfdcField":"Description"}]'
        );

        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-m2","data":{"email":"miss@example.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals('SUCCESS', logs[0].Status__c);
    }

    @IsTest
    static void testApplyMappings_invalidJson() {
        String badMappings = 'NOT_VALID_JSON';
        try {
            Contact c = new Contact(LastName = 'MapBad');
            ExtoleWebhookController.applyMappings(
                c,
                badMappings,
                new Map<String, Object>{ 'k' => 'v' }
            );
            System.assert(false, 'Expected exception');
        } catch (ExtoleApiException e) {
            System.assert(
                e.getMessage().contains('Invalid field mappings JSON')
            );
        }
    }

    // ── Multiple configs for same event ────────────────────────────────────────

    @IsTest
    static void testMultipleConfigs() {
        Contact c = new Contact(
            LastName = 'Multi',
            Email = 'multi@example.com'
        );
        Lead l = new Lead(
            LastName = 'Multi',
            Company = 'ACME',
            Email = 'multi@example.com'
        );
        insert c;
        insert l;
        makeConfig('reward_earned', 'Contact', null);
        makeConfig('reward_earned', 'Lead', null);

        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-mu1","data":{"email":"multi@example.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assert(
            RestContext.response.responseBody.toString()
                .contains('"processed":2')
        );
        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals(2, logs.size());
        for (Extole_Writeback_Log__c log : logs) {
            System.assertEquals('SUCCESS', log.Status__c);
        }
    }

    // ── findRecord unit tests ──────────────────────────────────────────────────

    @IsTest
    static void testFindRecord_contactByEmail() {
        Contact c = new Contact(LastName = 'FR1', Email = 'fr1@example.com');
        insert c;
        SObject result = ExtoleWebhookController.findRecord(
            'Contact',
            'fr1@example.com',
            null
        );
        System.assertNotEquals(null, result);
        System.assertEquals(c.Id, (String) result.get('Id'));
    }

    @IsTest
    static void testFindRecord_leadByEmail() {
        Lead l = new Lead(
            LastName = 'FR2',
            Company = 'ACME',
            Email = 'fr2@example.com'
        );
        insert l;
        SObject result = ExtoleWebhookController.findRecord(
            'Lead',
            'fr2@example.com',
            null
        );
        System.assertNotEquals(null, result);
        System.assertEquals(l.Id, (String) result.get('Id'));
    }

    @IsTest
    static void testFindRecord_unknownType() {
        SObject result = ExtoleWebhookController.findRecord(
            'Account',
            'x@x.com',
            null
        );
        System.assertEquals(null, result);
    }
}
