/**
 * ExtoleToolingServiceTest
 *
 * Coverage targets:
 *   - ExtoleToolingService.buildClassName
 *   - ExtoleToolingService.generateHandlerBody
 *   - ExtoleToolingService.translateToolingError
 *   - ExtoleToolingService.updateConfigTelemetry
 *   - ExtoleToolingService.deployHandlerClass (create + patch paths)
 *   - ExtoleToolingService.deleteHandlerClass
 *   - ExtoleToolingService.getApexClassId
 */
@isTest
private class ExtoleToolingServiceTest {

    // =========================================================================
    // Mock infrastructure
    // =========================================================================

    /**
     * Configurable mock that routes by endpoint substring.
     * Supports separate responses for GET /query, POST /ApexClass, PATCH, and DELETE.
     */
    private class ToolingMock implements HttpCalloutMock {
        // query → returns a record with a given Id (simulates class already exists)
        public String  queryRecordId  = null;   // null = not found
        public Integer postCode       = 201;
        public String  postBody       = '{"id":"abc000111222333"}';
        public Integer patchCode      = 204;
        public String  patchBody      = '';
        public Integer deleteCode     = 204;
        public String  deleteBody     = '';

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint();
            String method   = req.getMethod();

            if (method == 'GET' && endpoint.contains('/query')) {
                res.setStatusCode(200);
                if (queryRecordId != null) {
                    res.setBody('{"records":[{"Id":"' + queryRecordId + '"}],"totalSize":1,"done":true}');
                } else {
                    res.setBody('{"records":[],"totalSize":0,"done":true}');
                }
                return res;
            }
            if (method == 'POST' && endpoint.contains('/ApexClass')) {
                res.setStatusCode(postCode);
                res.setBody(postBody);
                return res;
            }
            if (method == 'PATCH' && endpoint.contains('/ApexClass')) {
                res.setStatusCode(patchCode);
                res.setBody(patchBody);
                return res;
            }
            if (method == 'DELETE' && endpoint.contains('/ApexClass')) {
                res.setStatusCode(deleteCode);
                res.setBody(deleteBody);
                return res;
            }

            res.setStatusCode(404);
            res.setBody('{"error":"unmatched"}');
            return res;
        }
    }

    // =========================================================================
    // buildClassName
    // =========================================================================

    @isTest
    static void testBuildClassName_version1() {
        System.assertEquals(
            'Extole_Handler_lead_abc123',
            ExtoleToolingService.buildClassName('lead_abc123', 1),
            'Version 1 should have no suffix'
        );
    }

    @isTest
    static void testBuildClassName_versionNull() {
        System.assertEquals(
            'Extole_Handler_lead_abc123',
            ExtoleToolingService.buildClassName('lead_abc123', null),
            'Null version should have no suffix'
        );
    }

    @isTest
    static void testBuildClassName_version2() {
        System.assertEquals(
            'Extole_Handler_lead_abc123_v2',
            ExtoleToolingService.buildClassName('lead_abc123', 2),
            'Version 2 should have _v2 suffix'
        );
    }

    @isTest
    static void testBuildClassName_version5() {
        System.assertEquals(
            'Extole_Handler_lead_abc123_v5',
            ExtoleToolingService.buildClassName('lead_abc123', 5),
            'Version 5 should have _v5 suffix'
        );
    }

    // =========================================================================
    // generateHandlerBody
    // =========================================================================

    @isTest
    static void testGenerateHandlerBody_directField() {
        String mappings = '[{"extole_param":"email","sfdc_field":"Email","static_value":null}]';
        String body = ExtoleToolingService.generateHandlerBody(
            'Extole_Handler_test_key', 'Lead', 'Id, Email', 'lead_created', mappings
        );
        System.assert(body.contains('class Extole_Handler_test_key'), 'Should contain class declaration');
        System.assert(body.contains('lead_created'), 'Should contain event name');
        System.assert(body.contains('Email'), 'Should contain mapped field');
        System.assert(body.contains('salesforce_crm'), 'Should inject app_type');
        System.assert(body.contains('callout:Extole_API/v5/events'), 'Should target Extole events endpoint');
    }

    @isTest
    static void testGenerateHandlerBody_staticValue() {
        String mappings = '[{"extole_param":"source","sfdc_field":null,"static_value":"salesforce"}]';
        String body = ExtoleToolingService.generateHandlerBody(
            'Extole_Handler_test_static', 'Lead', 'Id', 'lead_created', mappings
        );
        System.assert(body.contains('salesforce'), 'Should inject static value');
        System.assert(body.contains('dataMap.put(\'source\''), 'Should put static value into dataMap');
    }

    @isTest
    static void testGenerateHandlerBody_relationshipField() {
        String mappings = '[{"extole_param":"account_name","sfdc_field":"Account.Name","static_value":null}]';
        String body = ExtoleToolingService.generateHandlerBody(
            'Extole_Handler_test_rel', 'Contact', 'Id, Account.Name', 'contact_created', mappings
        );
        System.assert(body.contains('getSObject'), 'Should use getSObject for relationship fields');
        System.assert(body.contains('Account'), 'Should reference relationship object');
    }

    @isTest
    static void testGenerateHandlerBody_blankExtoleParam_skipped() {
        String mappings = '[{"extole_param":"","sfdc_field":"Email","static_value":null}]';
        String body = ExtoleToolingService.generateHandlerBody(
            'Extole_Handler_test_blank', 'Lead', 'Id', 'lead_created', mappings
        );
        // Blank extole_param should be silently skipped — body should still be valid
        System.assert(body.contains('class Extole_Handler_test_blank'), 'Class body should still be generated');
    }

    // =========================================================================
    // translateToolingError
    // =========================================================================

    @isTest
    static void testTranslateToolingError_403() {
        String msg = ExtoleToolingService.translateToolingError(403, '{}');
        System.assert(msg.contains('Author Apex'), '403 should mention Author Apex permission');
    }

    @isTest
    static void testTranslateToolingError_401() {
        String msg = ExtoleToolingService.translateToolingError(401, '{}');
        System.assert(msg.contains('Session expired') || msg.contains('log in'), '401 should mention session expiry');
    }

    @isTest
    static void testTranslateToolingError_fieldNotFound() {
        String errorBody = '[{"message":"field does not exist on Lead","errorCode":"INVALID_FIELD"}]';
        String msg = ExtoleToolingService.translateToolingError(400, errorBody);
        System.assert(msg.contains('does not exist'), 'Should surface field-not-found message');
    }

    @isTest
    static void testTranslateToolingError_notQueryable() {
        String errorBody = '[{"message":"field is not queryable in this context","errorCode":"INVALID_FIELD"}]';
        String msg = ExtoleToolingService.translateToolingError(400, errorBody);
        System.assert(msg.contains('not queryable'), 'Should surface not-queryable message');
    }

    @isTest
    static void testTranslateToolingError_genericApiError() {
        String msg = ExtoleToolingService.translateToolingError(500, '{"error":"internal"}');
        System.assert(msg.contains('500'), 'Generic error should include status code');
    }

    // =========================================================================
    // updateConfigTelemetry
    // =========================================================================

    @isTest
    static void testUpdateConfigTelemetry_success() {
        Extole_Event_Cfg__c cfg = new Extole_Event_Cfg__c(
            Config_Key__c     = 'test_key_telem',
            Event_Name__c     = 'lead_created',
            Trigger_Object__c = 'Lead',
            Active__c         = true,
            Apex_Class_Name__c = 'Extole_Handler_test_key_telem',
            Status__c         = 'ACTIVE',
            Field_Mappings_JSON__c = '[]'
        );
        insert cfg;

        DateTime before = DateTime.now();
        ExtoleToolingService.updateConfigTelemetry(
            'Extole_Handler_test_key_telem', '001000000000001AAA',
            before, true, 200, 'HTTP 200'
        );

        Extole_Event_Cfg__c updated = [
            SELECT Last_Succeeded_At__c, Last_HTTP_Status__c, Last_Response_Summary__c
            FROM Extole_Event_Cfg__c WHERE Id = :cfg.Id
        ];
        System.assertNotEquals(null, updated.Last_Succeeded_At__c, 'Last_Succeeded_At__c should be set on success');
        System.assertEquals(200, updated.Last_HTTP_Status__c, 'HTTP status should be recorded');
    }

    @isTest
    static void testUpdateConfigTelemetry_failure() {
        Extole_Event_Cfg__c cfg = new Extole_Event_Cfg__c(
            Config_Key__c     = 'test_key_fail',
            Event_Name__c     = 'lead_created',
            Trigger_Object__c = 'Lead',
            Active__c         = true,
            Apex_Class_Name__c = 'Extole_Handler_test_key_fail',
            Status__c         = 'ACTIVE',
            Field_Mappings_JSON__c = '[]'
        );
        insert cfg;

        DateTime before = DateTime.now();
        ExtoleToolingService.updateConfigTelemetry(
            'Extole_Handler_test_key_fail', '001000000000002AAA',
            before, false, 500, 'HTTP 500: Internal Error'
        );

        Extole_Event_Cfg__c updated = [
            SELECT Last_Failed_At__c, Last_HTTP_Status__c
            FROM Extole_Event_Cfg__c WHERE Id = :cfg.Id
        ];
        System.assertNotEquals(null, updated.Last_Failed_At__c, 'Last_Failed_At__c should be set on failure');
        System.assertEquals(500, updated.Last_HTTP_Status__c, 'HTTP status should be recorded');
    }

    @isTest
    static void testUpdateConfigTelemetry_notFound() {
        // Should not throw when class name has no matching config
        ExtoleToolingService.updateConfigTelemetry(
            'Extole_Handler_nonexistent', '001000000000003AAA',
            DateTime.now(), true, 200, 'HTTP 200'
        );
        System.assert(true, 'updateConfigTelemetry with no matching config should not throw');
    }

    // =========================================================================
    // deployHandlerClass — create path (class does not exist)
    // =========================================================================

    @isTest
    static void testDeployHandlerClass_createNew() {
        ToolingMock mock = new ToolingMock();
        mock.queryRecordId = null; // class doesn't exist yet
        mock.postCode = 201;
        mock.postBody = '{"id":"NEW_CLASS_ID_001"}';
        Test.setMock(HttpCalloutMock.class, mock);

        String mappings = '[{"extole_param":"email","sfdc_field":"Email","static_value":null}]';
        ExtoleToolingService.sessionOverride = 'fake-session-token';

        Test.startTest();
        String classId = ExtoleToolingService.deployHandlerClass(
            'lead_test_key', 1, 'Lead', 'Id, Email', 'lead_created', mappings
        );
        Test.stopTest();

        System.assertEquals('NEW_CLASS_ID_001', classId, 'Should return new class Id');
    }

    // =========================================================================
    // deployHandlerClass — patch path (class already exists)
    // =========================================================================

    @isTest
    static void testDeployHandlerClass_patchExisting() {
        ToolingMock mock = new ToolingMock();
        mock.queryRecordId = 'EXISTING_ID_999'; // class exists
        mock.patchCode = 204;
        Test.setMock(HttpCalloutMock.class, mock);

        String mappings = '[{"extole_param":"email","sfdc_field":"Email","static_value":null}]';
        ExtoleToolingService.sessionOverride = 'fake-session-token';

        Test.startTest();
        String classId = ExtoleToolingService.deployHandlerClass(
            'lead_existing_key', 1, 'Lead', 'Id, Email', 'lead_created', mappings
        );
        Test.stopTest();

        System.assertEquals('EXISTING_ID_999', classId, 'Patch should return existing class Id');
    }

    // =========================================================================
    // deleteHandlerClass
    // =========================================================================

    @isTest
    static void testDeleteHandlerClass_found() {
        ToolingMock mock = new ToolingMock();
        mock.queryRecordId = 'DELETE_ID_001';
        mock.deleteCode = 204;
        Test.setMock(HttpCalloutMock.class, mock);

        ExtoleToolingService.sessionOverride = 'fake-session-token';

        Test.startTest();
        ExtoleToolingService.deleteHandlerClass('Extole_Handler_some_key');
        Test.stopTest();

        System.assert(true, 'deleteHandlerClass should complete without exception');
    }

    @isTest
    static void testDeleteHandlerClass_notFound() {
        ToolingMock mock = new ToolingMock();
        mock.queryRecordId = null; // class doesn't exist
        Test.setMock(HttpCalloutMock.class, mock);

        ExtoleToolingService.sessionOverride = 'fake-session-token';

        Test.startTest();
        ExtoleToolingService.deleteHandlerClass('Extole_Handler_nonexistent');
        Test.stopTest();

        System.assert(true, 'deleteHandlerClass on missing class should not throw');
    }

    // =========================================================================
    // getApexClassId
    // =========================================================================

    @isTest
    static void testGetApexClassId_found() {
        ToolingMock mock = new ToolingMock();
        mock.queryRecordId = 'FOUND_ID_123';
        Test.setMock(HttpCalloutMock.class, mock);

        ExtoleToolingService.sessionOverride = 'fake-session-token';

        Test.startTest();
        String id = ExtoleToolingService.getApexClassId('Extole_Handler_some_key');
        Test.stopTest();

        System.assertEquals('FOUND_ID_123', id, 'Should return the class Id');
    }

    @isTest
    static void testGetApexClassId_notFound() {
        ToolingMock mock = new ToolingMock();
        mock.queryRecordId = null;
        Test.setMock(HttpCalloutMock.class, mock);

        ExtoleToolingService.sessionOverride = 'fake-session-token';

        Test.startTest();
        String id = ExtoleToolingService.getApexClassId('Extole_Handler_missing');
        Test.stopTest();

        System.assertEquals(null, id, 'Should return null when class not found');
    }
}
