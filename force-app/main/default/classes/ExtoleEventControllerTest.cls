@IsTest
private class ExtoleEventControllerTest {
    private static Extole_Event_Cfg__c makeConfig(
        String key,
        String status,
        String flowName
    ) {
        Extole_Event_Cfg__c cfg = new Extole_Event_Cfg__c(
            Config_Key__c = key,
            Event_Name__c = key,
            Trigger_Object__c = 'Lead',
            Trigger_Type__c = 'CREATED',
            Status__c = status,
            Flow_Name__c = flowName
        );
        insert cfg;
        return cfg;
    }

    // Matches the Tooling-callout mock pattern established in ExtoleEventHandlerTest.
    private class ConfigurableMock implements HttpCalloutMock {
        private List<String> patterns = new List<String>();
        private List<Integer> codes = new List<Integer>();
        private List<String> bodies = new List<String>();
        private Integer defaultCode = 200;
        private String defaultBody = '{}';

        public ConfigurableMock withDefault(Integer code, String body) {
            defaultCode = code;
            defaultBody = body;
            return this;
        }
        public ConfigurableMock addPattern(
            String pattern,
            Integer code,
            String body
        ) {
            patterns.add(pattern);
            codes.add(code);
            bodies.add(body);
            return this;
        }
        public HttpResponse respond(HttpRequest req) {
            String endpoint = req.getEndpoint();
            for (Integer i = 0; i < patterns.size(); i++) {
                if (endpoint.contains(patterns[i])) {
                    HttpResponse r = new HttpResponse();
                    r.setStatusCode(codes[i]);
                    r.setBody(bodies[i]);
                    return r;
                }
            }
            HttpResponse def = new HttpResponse();
            def.setStatusCode(defaultCode);
            def.setBody(defaultBody);
            return def;
        }
    }

    // ── getPicklistValues ─────────────────────────────────────────────────────

    @IsTest
    static void testGetPicklistValues_returnsActiveEntries() {
        Test.startTest();
        List<Map<String, Object>> values = ExtoleEventController.getPicklistValues(
            'Lead',
            'LeadSource'
        );
        Test.stopTest();

        System.assert(values.size() > 0);
        System.assertNotEquals(null, values[0].get('label'));
        System.assertNotEquals(null, values[0].get('value'));
    }

    @IsTest
    static void testGetPicklistValues_blankInputsReturnEmpty() {
        Test.startTest();
        List<Map<String, Object>> v1 = ExtoleEventController.getPicklistValues(
            '',
            'LeadSource'
        );
        List<Map<String, Object>> v2 = ExtoleEventController.getPicklistValues(
            'Lead',
            ''
        );
        Test.stopTest();

        System.assertEquals(0, v1.size());
        System.assertEquals(0, v2.size());
    }

    @IsTest
    static void testGetPicklistValues_unknownObjectReturnsEmpty() {
        Test.startTest();
        List<Map<String, Object>> values = ExtoleEventController.getPicklistValues(
            'Not_A_Real_Object__x',
            'Foo'
        );
        Test.stopTest();
        System.assertEquals(0, values.size());
    }

    @IsTest
    static void testGetPicklistValues_unknownFieldReturnsEmpty() {
        Test.startTest();
        List<Map<String, Object>> values = ExtoleEventController.getPicklistValues(
            'Lead',
            'not_a_real_field__x'
        );
        Test.stopTest();
        System.assertEquals(0, values.size());
    }

    // ── suggestUniqueEventName ────────────────────────────────────────────────

    @IsTest
    static void testSuggestUniqueEventName_blankInputReturnsAsIs() {
        Test.startTest();
        String result = ExtoleEventController.suggestUniqueEventName('', null);
        Test.stopTest();
        System.assertEquals('', result);
    }

    @IsTest
    static void testSuggestUniqueEventName_noConflictReturnsAsIs() {
        Test.startTest();
        String result = ExtoleEventController.suggestUniqueEventName(
            'brand_new_event',
            null
        );
        Test.stopTest();
        System.assertEquals('brand_new_event', result);
    }

    @IsTest
    static void testSuggestUniqueEventName_conflictAppendsSuffix() {
        makeConfig('existing_cfg', 'ACTIVE', null);
        Extole_Event_Cfg__c cfg = [
            SELECT Id, Event_Name__c
            FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = 'existing_cfg'
        ];
        cfg.Event_Name__c = 'lead_created';
        update cfg;

        Test.startTest();
        String result = ExtoleEventController.suggestUniqueEventName(
            'lead_created',
            null
        );
        Test.stopTest();

        System.assertEquals('lead_created_2', result);
    }

    @IsTest
    static void testSuggestUniqueEventName_excludesCurrentConfig() {
        makeConfig('self_cfg', 'ACTIVE', null);
        Extole_Event_Cfg__c cfg = [
            SELECT Id, Event_Name__c
            FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = 'self_cfg'
        ];
        cfg.Event_Name__c = 'lead_created';
        update cfg;

        Test.startTest();
        // Excluding self_cfg means its own event name shouldn't count as a conflict.
        String result = ExtoleEventController.suggestUniqueEventName(
            'lead_created',
            'self_cfg'
        );
        Test.stopTest();

        System.assertEquals('lead_created', result);
    }

    // ── deleteEventConfig / deactivateEventConfig ────────────────────────────

    @IsTest
    static void testDeleteEventConfig_notFoundThrows() {
        Boolean threw = false;
        try {
            ExtoleEventController.deleteEventConfig('nonexistent');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testDeleteEventConfig_noFlowNameDeletesRecord() {
        Extole_Event_Cfg__c cfg = makeConfig('to_delete', 'DRAFT', null);

        Test.startTest();
        ExtoleEventController.deleteEventConfig('to_delete');
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Extole_Event_Cfg__c WHERE Id = :cfg.Id]
        );
        List<Extole_Event_Log__c> logs = [
            SELECT Event_Type__c
            FROM Extole_Event_Log__c
            WHERE Config_Key__c = 'to_delete'
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('CONFIG_DELETED', logs[0].Event_Type__c);
    }

    @IsTest
    static void testDeactivateEventConfig_notFoundThrows() {
        Boolean threw = false;
        try {
            ExtoleEventController.deactivateEventConfig('nonexistent');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testDeactivateEventConfig_noFlowNameUpdatesStatus() {
        Extole_Event_Cfg__c cfg = makeConfig('to_deactivate', 'ACTIVE', null);

        Test.startTest();
        ExtoleEventController.deactivateEventConfig('to_deactivate');
        Test.stopTest();

        Extole_Event_Cfg__c updated = [
            SELECT Status__c, Active__c
            FROM Extole_Event_Cfg__c
            WHERE Id = :cfg.Id
        ];
        System.assertEquals('INACTIVE', updated.Status__c);
        System.assertEquals(false, updated.Active__c);
    }

    // ── Event Fire Log ────────────────────────────────────────────────────────

    @IsTest
    static void testGetEventFireLogsAndClear() {
        insert new Extole_Event_Fire_Log__c(
            Config_Key__c = 'x',
            Event_Name__c = 'lead_created',
            Result__c = 'SUCCESS',
            Timestamp__c = DateTime.now()
        );

        Test.startTest();
        List<Extole_Event_Fire_Log__c> logs = ExtoleEventController.getEventFireLogs();
        System.assertEquals(1, logs.size());

        Map<String, Integer> result = ExtoleEventController.clearEventFireLogs();
        Test.stopTest();

        System.assertEquals(1, result.get('deletedCount'));
        System.assertEquals(0, result.get('remainingCount'));
    }

    @IsTest
    static void testClearEventLog() {
        insert new Extole_Event_Log__c(
            Config_Key__c = 'x',
            Event_Type__c = 'CONFIG_CREATED',
            Result__c = 'SUCCESS',
            Timestamp__c = DateTime.now()
        );

        Test.startTest();
        Map<String, Integer> result = ExtoleEventController.clearEventLog();
        Test.stopTest();

        System.assertEquals(1, result.get('deletedCount'));
        System.assertEquals(0, result.get('remainingCount'));
    }

    // ── pollDeployStatus pending branch ──────────────────────────────────────

    @IsTest
    static void testPollDeployStatus_pendingForDraftConfig() {
        makeConfig('poll_pending_cfg', 'DRAFT', null);

        Test.startTest();
        Map<String, Object> result = ExtoleEventController.pollDeployStatus(
            'poll_pending_cfg'
        );
        Test.stopTest();

        System.assertEquals('PENDING', result.get('status'));
    }

    @IsTest
    static void testPollDeployStatus_blankJobIdReturnsFailed() {
        Test.startTest();
        Map<String, Object> result = ExtoleEventController.pollDeployStatus('');
        Test.stopTest();

        System.assertEquals('FAILED', result.get('status'));
        System.assertEquals('No jobId provided', result.get('errorMessage'));
    }

    // ── previewPayload edge branches ─────────────────────────────────────────

    @IsTest
    static void testPreviewPayload_missingTriggerObjectOrMappingsThrows() {
        Lead l = new Lead(
            LastName = 'X',
            Company = 'Acme',
            Email = 'x@example.com'
        );
        insert l;
        Boolean threw = false;
        try {
            ExtoleEventController.previewPayload('{"eventName":"e"}', l.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testPreviewPayload_recordNotFoundThrows() {
        Boolean threw = false;
        try {
            ExtoleEventController.previewPayload(
                '{"eventName":"e","triggerObject":"Lead","fieldMappingsJson":"[]"}',
                '00Q000000000000AAA'
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testPreviewPayload_dotNotationRelationshipField() {
        Account acct = new Account(Name = 'Acme Corp');
        insert acct;
        Contact c = new Contact(
            LastName = 'Test',
            Email = 'c@example.com',
            AccountId = acct.Id
        );
        insert c;

        String configJson =
            '{"eventName":"contact_created","triggerObject":"Contact",' +
            '"fieldMappingsJson":"[{\\"extole_param\\":\\"account_name\\",\\"sfdc_field\\":\\"Account.Name\\",\\"static_value\\":null}]"}';

        Test.startTest();
        String payload = ExtoleEventController.previewPayload(configJson, c.Id);
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
            payload
        );
        Map<String, Object> data = (Map<String, Object>) parsed.get('data');
        System.assertEquals('Acme Corp', data.get('account_name'));
    }

    // ── deployEventConfig: derive configKey from name, and failure path ─────

    @IsTest
    static void testDeployEventConfig_derivesConfigKeyFromEventNameAndTriggerObject() {
        insert new Extole_Event_Cfg__c(
            Config_Key__c = 'Lead_derived_key_event',
            Event_Name__c = 'derived_key_event',
            Trigger_Object__c = 'Lead',
            Trigger_Type__c = 'CREATED',
            Field_Mappings_JSON__c = '[]',
            Status__c = 'DRAFT'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new ConfigurableMock()
                .addPattern(
                    '/query/',
                    200,
                    '{"records":[],"totalSize":0,"done":true}'
                )
                .addPattern(
                    '/sobjects/Flow/',
                    201,
                    '{"id":"301DERIVED001","success":true}'
                )
        );

        String configJson =
            '{"eventName":"derived_key_event","triggerObject":"Lead","triggerType":"CREATED",' +
            '"fieldMappingsJson":"[]"}';

        Test.startTest();
        String jobId = ExtoleEventController.deployEventConfig(configJson);
        Test.stopTest();

        System.assertEquals('Lead_derived_key_event', jobId);
        Extole_Event_Cfg__c updated = [
            SELECT Status__c
            FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = 'Lead_derived_key_event'
        ];
        System.assertEquals('ACTIVE', updated.Status__c);
    }

    @IsTest
    static void testDeployEventConfig_missingConfigKeyAndNames_throws() {
        Boolean threw = false;
        try {
            ExtoleEventController.deployEventConfig(
                '{"triggerType":"CREATED"}'
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testDeployEventConfig_deployFailureMarksConfigFailed() {
        insert new Extole_Event_Cfg__c(
            Config_Key__c = 'Lead_fail_deploy',
            Event_Name__c = 'fail_deploy',
            Trigger_Object__c = 'Lead',
            Trigger_Type__c = 'CREATED',
            Field_Mappings_JSON__c = '[]',
            Status__c = 'DRAFT'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new ConfigurableMock()
                .addPattern(
                    '/query/',
                    200,
                    '{"records":[],"totalSize":0,"done":true}'
                )
                .addPattern(
                    '/sobjects/Flow/',
                    403,
                    '{"message":"Forbidden","errorCode":"FORBIDDEN"}'
                )
        );

        String configJson =
            '{"configKey":"Lead_fail_deploy","eventName":"fail_deploy",' +
            '"triggerObject":"Lead","triggerType":"CREATED","fieldMappingsJson":"[]"}';

        Test.startTest();
        ExtoleEventController.deployEventConfig(configJson);
        Test.stopTest();

        Extole_Event_Cfg__c updated = [
            SELECT Status__c, Deploy_Error__c
            FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = 'Lead_fail_deploy'
        ];
        System.assertEquals('DEPLOY_FAILED', updated.Status__c);
        System.assertNotEquals(null, updated.Deploy_Error__c);

        List<Extole_Event_Log__c> logs = [
            SELECT Event_Type__c
            FROM Extole_Event_Log__c
            WHERE
                Config_Key__c = 'Lead_fail_deploy'
                AND Event_Type__c = 'DEPLOY_FAILED'
        ];
        System.assertEquals(1, logs.size());
    }

    // ── delete/deactivate with a real flow name set ──────────────────────────

    @IsTest
    static void testDeleteEventConfig_withFlowNameAttemptsCleanup() {
        Extole_Event_Cfg__c cfg = makeConfig(
            'to_delete_with_flow',
            'ACTIVE',
            'Extole_Flow_to_delete_with_flow'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new ConfigurableMock()
                .addPattern(
                    '/query/',
                    200,
                    '{"records":[],"totalSize":0,"done":true}'
                )
        );

        Test.startTest();
        ExtoleEventController.deleteEventConfig('to_delete_with_flow');
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Extole_Event_Cfg__c WHERE Id = :cfg.Id]
        );
    }

    @IsTest
    static void testDeactivateEventConfig_withFlowNameAttemptsDeactivation() {
        Extole_Event_Cfg__c cfg = makeConfig(
            'to_deactivate_with_flow',
            'ACTIVE',
            'Extole_Flow_to_deactivate_with_flow'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new ConfigurableMock()
                .addPattern(
                    '/query/',
                    200,
                    '{"records":[],"totalSize":0,"done":true}'
                )
        );

        Test.startTest();
        ExtoleEventController.deactivateEventConfig('to_deactivate_with_flow');
        Test.stopTest();

        Extole_Event_Cfg__c updated = [
            SELECT Status__c
            FROM Extole_Event_Cfg__c
            WHERE Id = :cfg.Id
        ];
        System.assertEquals('INACTIVE', updated.Status__c);
    }
}
