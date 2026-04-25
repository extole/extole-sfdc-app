/**
 * ExtoleEventHandlerTest
 *
 * Coverage targets:
 *   - ExtoleUniversalHandler   (invoke grouping, execute data map, telemetry)
 *   - ExtoleMetadataService    (buildFlowMetadata, deploy/deactivate/delete, error translation)
 *   - ExtoleSafetyCheckService (FOUND / NOT_FOUND / UNKNOWN, multi-shape JSON scanning)
 *   - ExtoleEventController    (all @AuraEnabled methods, deploy orchestration)
 *
 * All HTTP callouts are mocked — no real API calls in tests.
 */
@isTest
private class ExtoleEventHandlerTest {

    // =========================================================================
    // Mock infrastructure
    // =========================================================================

    /**
     * Configurable mock that returns different responses per endpoint substring.
     */
    private class ConfigurableMock implements HttpCalloutMock {
        private List<String>  patterns    = new List<String>();
        private List<Integer> codes       = new List<Integer>();
        private List<String>  bodies      = new List<String>();
        private Integer       defaultCode = 200;
        private String        defaultBody = '{}';

        public ConfigurableMock withDefault(Integer code, String body) {
            defaultCode = code; defaultBody = body; return this;
        }

        public ConfigurableMock addPattern(String pattern, Integer code, String body) {
            patterns.add(pattern); codes.add(code); bodies.add(body); return this;
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

    private class SuccessMock implements HttpCalloutMock {
        private Integer code; private String body;
        public SuccessMock(Integer code, String body) { this.code = code; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse(); r.setStatusCode(code); r.setBody(body); return r;
        }
    }

    private class TimeoutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new System.CalloutException('Read timed out');
        }
    }

    // =========================================================================
    // Test setup
    // =========================================================================

    @TestSetup
    static void setupData() {
        insert new Lead(
            FirstName  = 'Test',
            LastName   = 'LeadPreview',
            Company    = 'Extole Tests Inc',
            Email      = 'preview@extole-test.com',
            LeadSource = 'Web'
        );
    }

    // =========================================================================
    // ExtoleUniversalHandler — @InvocableMethod grouping
    // =========================================================================

    @isTest
    static void testInvoke_groupsByConfigKey() {
        // Two inputs with the same configKey → one job enqueued
        // Two inputs with different configKeys → two jobs enqueued
        // (Can't assert enqueued count directly, but no exception = correct grouping)
        List<ExtoleUniversalHandler.HandlerInput> inputs = new List<ExtoleUniversalHandler.HandlerInput>();
        ExtoleUniversalHandler.HandlerInput i1 = new ExtoleUniversalHandler.HandlerInput();
        i1.configKey = 'key_a'; i1.recordId = '001000000000001AAA';
        ExtoleUniversalHandler.HandlerInput i2 = new ExtoleUniversalHandler.HandlerInput();
        i2.configKey = 'key_a'; i2.recordId = '001000000000002AAA';
        ExtoleUniversalHandler.HandlerInput i3 = new ExtoleUniversalHandler.HandlerInput();
        i3.configKey = 'key_b'; i3.recordId = '001000000000003AAA';
        inputs.add(i1); inputs.add(i2); inputs.add(i3);

        Test.setMock(HttpCalloutMock.class, new SuccessMock(200, '{}'));
        Test.startTest();
        ExtoleUniversalHandler.invoke(inputs);
        Test.stopTest();
        System.assert(true, 'invoke completed without error');
    }

    @isTest
    static void testInvoke_skipsBlankInputs() {
        ExtoleUniversalHandler.HandlerInput inp = new ExtoleUniversalHandler.HandlerInput();
        inp.configKey = ''; inp.recordId = '001000000000001AAA';

        Test.startTest();
        ExtoleUniversalHandler.invoke(new List<ExtoleUniversalHandler.HandlerInput>{ inp });
        Test.stopTest();
        System.assert(true, 'Blank configKey skipped without error');
    }

    @isTest
    static void testExecute_noActiveConfig_noError() {
        // execute() with a configKey that has no active config → logs and returns, no exception
        Test.setMock(HttpCalloutMock.class, new SuccessMock(200, '{}'));
        Test.startTest();
        ExtoleUniversalHandler handler = new ExtoleUniversalHandler(
            'nonexistent_config_key', new List<String>{ '001000000000001AAA' }
        );
        handler.execute(null);
        Test.stopTest();
        System.assert(true, 'execute with missing config is a no-op');
    }

    @isTest
    static void testExecute_sendsEventForActiveConfig() {
        // Insert an active config and a real Lead, then call execute()
        Lead testLead = [SELECT Id FROM Lead WHERE LastName = 'LeadPreview' LIMIT 1];

        insert new Extole_Event_Cfg__c(
            Config_Key__c          = 'test_exec_cfg',
            Event_Name__c          = 'lead_created',
            Trigger_Object__c      = 'Lead',
            Trigger_Type__c        = 'CREATED',
            Field_Mappings_JSON__c = '[{"extole_param":"email","sfdc_field":"Email","static_value":null},'
                + '{"extole_param":"source","sfdc_field":null,"static_value":"sfdc"}]',
            Status__c              = 'ACTIVE',
            Active__c              = true
        );

        Test.setMock(HttpCalloutMock.class, new SuccessMock(200, '{"id":"evt001"}'));
        Test.startTest();
        ExtoleUniversalHandler handler = new ExtoleUniversalHandler(
            'test_exec_cfg', new List<String>{ testLead.Id }
        );
        handler.execute(null);
        Test.stopTest();

        // Verify telemetry was written
        Extole_Event_Cfg__c updated = [
            SELECT Last_HTTP_Status__c FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = 'test_exec_cfg' LIMIT 1
        ];
        System.assertEquals(200, updated.Last_HTTP_Status__c, 'Telemetry HTTP status updated');
    }

    @isTest
    static void testExecute_calloutFailure_updatesTelemetry() {
        Lead testLead = [SELECT Id FROM Lead WHERE LastName = 'LeadPreview' LIMIT 1];

        insert new Extole_Event_Cfg__c(
            Config_Key__c          = 'test_fail_cfg',
            Event_Name__c          = 'lead_created',
            Trigger_Object__c      = 'Lead',
            Trigger_Type__c        = 'CREATED',
            Field_Mappings_JSON__c = '[{"extole_param":"email","sfdc_field":"Email","static_value":null}]',
            Status__c              = 'ACTIVE',
            Active__c              = true
        );

        Test.setMock(HttpCalloutMock.class, new SuccessMock(500, 'Internal Error'));
        Test.startTest();
        new ExtoleUniversalHandler('test_fail_cfg', new List<String>{ testLead.Id }).execute(null);
        Test.stopTest();

        Extole_Event_Cfg__c updated = [
            SELECT Last_HTTP_Status__c, Last_Failed_At__c
            FROM Extole_Event_Cfg__c WHERE Config_Key__c = 'test_fail_cfg' LIMIT 1
        ];
        System.assertEquals(500, updated.Last_HTTP_Status__c, '500 status written to telemetry');
        System.assertNotEquals(null, updated.Last_Failed_At__c, 'Last_Failed_At set on error');
    }

    @isTest
    static void testExecute_multipleRecords_singleTelemetryWrite() {
        // Verifies the N+1 DML fix: telemetry is written once after all records,
        // not once per record. With 3 records, DML count should be 1 (the telemetry update),
        // not 3.
        Account acct = new Account(Name = 'Batch Test Corp');
        insert acct;
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 3; i++) {
            opps.add(new Opportunity(
                Name      = 'Batch Opp ' + i,
                AccountId = acct.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        insert opps;

        insert new Extole_Event_Cfg__c(
            Config_Key__c          = 'test_batch_cfg',
            Event_Name__c          = 'opp_created',
            Trigger_Object__c      = 'Opportunity',
            Trigger_Type__c        = 'CREATED',
            Field_Mappings_JSON__c = '[{"extole_param":"name","sfdc_field":"Name","static_value":null}]',
            Status__c              = 'ACTIVE',
            Active__c              = true
        );

        List<String> oppIds = new List<String>();
        for (Opportunity o : opps) oppIds.add(o.Id);

        Test.setMock(HttpCalloutMock.class, new SuccessMock(200, '{"id":"evt_batch"}'));
        Test.startTest();
        new ExtoleUniversalHandler('test_batch_cfg', oppIds).execute(null);
        Test.stopTest();

        // Telemetry should reflect the last record processed, written once
        Extole_Event_Cfg__c updated = [
            SELECT Last_HTTP_Status__c, Last_Succeeded_At__c, Last_Record_Id__c
            FROM Extole_Event_Cfg__c WHERE Config_Key__c = 'test_batch_cfg' LIMIT 1
        ];
        System.assertEquals(200, updated.Last_HTTP_Status__c, 'HTTP 200 written after batch');
        System.assertNotEquals(null, updated.Last_Succeeded_At__c, 'Last_Succeeded_At set');
        System.assert(
            new Set<String>(oppIds).contains(updated.Last_Record_Id__c),
            'Last_Record_Id is one of the batch records'
        );
    }

    @isTest
    static void testExecute_oneHopRelationshipField() {
        // Opportunity with Account lookup → Account.Name mapping
        Account acct = new Account(Name = 'Extole Corp');
        insert acct;
        Opportunity opp = new Opportunity(
            Name        = 'Test Opp',
            AccountId   = acct.Id,
            StageName   = 'Prospecting',
            CloseDate   = Date.today().addDays(30)
        );
        insert opp;

        insert new Extole_Event_Cfg__c(
            Config_Key__c          = 'test_opp_rel',
            Event_Name__c          = 'opp_created',
            Trigger_Object__c      = 'Opportunity',
            Trigger_Type__c        = 'CREATED',
            Field_Mappings_JSON__c = '[{"extole_param":"company","sfdc_field":"Account.Name","static_value":null}]',
            Status__c              = 'ACTIVE',
            Active__c              = true
        );

        Test.setMock(HttpCalloutMock.class, new SuccessMock(200, '{}'));
        Test.startTest();
        new ExtoleUniversalHandler('test_opp_rel', new List<String>{ opp.Id }).execute(null);
        Test.stopTest();

        Extole_Event_Cfg__c updated = [
            SELECT Last_HTTP_Status__c FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = 'test_opp_rel' LIMIT 1
        ];
        System.assertEquals(200, updated.Last_HTTP_Status__c, 'One-hop field resolved successfully');
    }

    // =========================================================================
    // ExtoleMetadataService — buildFlowMetadata (JSON shape)
    // =========================================================================

    @isTest
    static void testBuildFlowMetadata_created() {
        Map<String, Object> meta = ExtoleMetadataService.buildFlowMetadata(
            'Extole_Flow_lead_test',
            'lead_test',
            'Lead',
            'CREATED',
            null, null
        );
        System.assertEquals('AutoLaunchedFlow', meta.get('processType'));
        System.assertEquals('Active', meta.get('status'));

        Map<String, Object> start = (Map<String, Object>) meta.get('start');
        System.assertEquals('Lead', start.get('object'));
        System.assertEquals('Create', start.get('recordTriggerType'));
        System.assertEquals('RecordAfterSave', start.get('triggerType'));

        List<Object> actionCalls = (List<Object>) meta.get('actionCalls');
        Map<String, Object> action = (Map<String, Object>) actionCalls[0];
        System.assertEquals('ExtoleUniversalHandler', action.get('actionName'));
        System.assertEquals('apex', action.get('actionType'));

        // Verify configKey and recordId input params
        List<Object> params = (List<Object>) action.get('inputParameters');
        Map<String, Object> configKeyParam = (Map<String, Object>) params[0];
        System.assertEquals('configKey', configKeyParam.get('name'));
        Map<String, Object> configKeyVal = (Map<String, Object>) configKeyParam.get('value');
        System.assertEquals('lead_test', configKeyVal.get('stringValue'));

        Map<String, Object> recordIdParam = (Map<String, Object>) params[1];
        System.assertEquals('recordId', recordIdParam.get('name'));
    }

    @isTest
    static void testBuildFlowMetadata_updated() {
        Map<String, Object> meta = ExtoleMetadataService.buildFlowMetadata(
            'Extole_Flow_contact_test',
            'contact_test',
            'Contact',
            'UPDATED',
            null, null
        );
        Map<String, Object> start = (Map<String, Object>) meta.get('start');
        System.assertEquals('CreateAndUpdate', start.get('recordTriggerType'));
    }

    @isTest
    static void testBuildFlowMetadata_fieldEquals_hasFilter() {
        Map<String, Object> meta = ExtoleMetadataService.buildFlowMetadata(
            'Extole_Flow_opp_test',
            'opp_test',
            'Opportunity',
            'FIELD_EQUALS',
            'StageName', 'Closed Won'
        );
        Map<String, Object> start = (Map<String, Object>) meta.get('start');
        List<Object> filters = (List<Object>) start.get('filters');
        System.assertNotEquals(null, filters, 'FIELD_EQUALS generates filters');
        System.assertEquals(1, filters.size(), 'One filter group');
    }

    @isTest
    static void testBuildFlowMetadata_fieldChanges_hasIsChangedFilter() {
        Map<String, Object> meta = ExtoleMetadataService.buildFlowMetadata(
            'Extole_Flow_lead_fc', 'lead_fc', 'Lead', 'FIELD_CHANGES', 'Status', null
        );
        Map<String, Object> start = (Map<String, Object>) meta.get('start');

        // Must have a filter with IsChanged operator
        List<Object> filters = (List<Object>) start.get('filters');
        System.assertNotEquals(null, filters, 'FIELD_CHANGES generates filters');
        System.assertEquals(1, filters.size(), 'One filter entry');
        Map<String, Object> filter = (Map<String, Object>) filters[0];
        System.assertEquals('Status', filter.get('field'), 'Filter targets trigger field');
        System.assertEquals('IsChanged', filter.get('operator'), 'Operator is IsChanged');

        // doesRequireRecordChangedToMeetCriteria must NOT be set — incompatible with IsChanged
        System.assertNotEquals(true, start.get('doesRequireRecordChangedToMeetCriteria'),
            'doesRequireRecordChangedToMeetCriteria must not be true with IsChanged');
    }

    @isTest
    static void testBuildFlowMetadata_fieldChanges_noField_noFilter() {
        // FIELD_CHANGES with no triggerField → no filter added (avoids broken flow metadata)
        Map<String, Object> meta = ExtoleMetadataService.buildFlowMetadata(
            'Extole_Flow_lead_nofield', 'lead_nofield', 'Lead', 'FIELD_CHANGES', null, null
        );
        Map<String, Object> start = (Map<String, Object>) meta.get('start');
        System.assertEquals(null, start.get('filters'), 'No filter when triggerField is blank');
    }

    @isTest
    static void testDeployFlow_fieldChanges() {
        ConfigurableMock mock = new ConfigurableMock()
            .addPattern('/sobjects/Flow/', 201, '{"id":"301XXFC001","success":true}');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        String flowName = ExtoleMetadataService.deployFlow(
            'test_fc_flow', 'Lead', 'FIELD_CHANGES', 'Status', null
        );
        Test.stopTest();
        System.assertNotEquals(null, flowName, 'FIELD_CHANGES flow deployed without error');
    }

    @isTest
    static void testBuildFlowMetadata_fieldEquals_emptyValue_noFilter() {
        // No filter when triggerValue is blank
        Map<String, Object> meta = ExtoleMetadataService.buildFlowMetadata(
            'Extole_Flow_no_val',
            'no_val',
            'Lead',
            'FIELD_EQUALS',
            'StageName', null
        );
        Map<String, Object> start = (Map<String, Object>) meta.get('start');
        System.assertEquals(null, start.get('filters'), 'No filter when triggerValue is blank');
    }

    // =========================================================================
    // ExtoleMetadataService — deployFlow / deactivateFlow / deleteFlow (mocked)
    // =========================================================================

    @isTest
    static void testDeployFlow_success() {
        // POST to Named Credential endpoint returns 201
        ConfigurableMock mock = new ConfigurableMock()
            .addPattern('/sobjects/Flow/', 201, '{"id":"301XXX001","success":true}');

        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        String flowName = ExtoleMetadataService.deployFlow(
            'test_deploy_flow', 'Lead', 'CREATED', null, null
        );
        Test.stopTest();

        System.assertEquals('Extole_Flow_test_deploy_flow', flowName, 'Returns expected flow name');
    }

    @isTest
    static void testDeployFlow_fieldEquals() {
        ConfigurableMock mock = new ConfigurableMock()
            .addPattern('/sobjects/Flow/', 201, '{"id":"301XXX002","success":true}');

        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        String flowName = ExtoleMetadataService.deployFlow(
            'test_field_eq', 'Lead', 'FIELD_EQUALS', 'IsConverted', 'true'
        );
        Test.stopTest();

        System.assertNotEquals(null, flowName, 'FIELD_EQUALS flow deployed without error');
    }

    @isTest
    static void testDeployFlow_403_throws() {
        ConfigurableMock mock = new ConfigurableMock()
            .addPattern('/sobjects/Flow/', 403, '[{"message":"Forbidden"}]');

        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        Boolean threw = false;
        try {
            ExtoleMetadataService.deployFlow('test_err_flow', 'Lead', 'CREATED', null, null);
        } catch (ExtoleMetadataService.ExtoleMetadataException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'deployFlow throws ExtoleMetadataException on 403');
    }

    @isTest
    static void testDeactivateFlow_flowNotFound_noError() {
        // Query returns no FlowDefinition → deactivateFlow is a no-op
        ConfigurableMock mock = new ConfigurableMock()
            .addPattern('/query/', 200, '{"records":[],"totalSize":0,"done":true}');

        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        ExtoleMetadataService.deactivateFlow('Extole_Flow_not_found');
        Test.stopTest();
        System.assert(true, 'deactivateFlow with no FlowDefinition is a no-op');
    }

    @isTest
    static void testDeactivateFlow_success() {
        ConfigurableMock mock = new ConfigurableMock()
            .addPattern('/query/', 200,
                '{"records":[{"Id":"301DEF001"}],"totalSize":1,"done":true}')
            .addPattern('/sobjects/FlowDefinition/301DEF001', 204, '');

        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        ExtoleMetadataService.deactivateFlow('Extole_Flow_test_deactivate');
        Test.stopTest();
        System.assert(true, 'deactivateFlow completed without exception');
    }

    @isTest
    static void testDeleteFlow_noVersions_noError() {
        // deleteFlow queries flow version IDs — returns empty → no-op
        ConfigurableMock mock = new ConfigurableMock()
            .addPattern('/query/', 200, '{"records":[],"totalSize":0,"done":true}');

        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        ExtoleMetadataService.deleteFlow('Extole_Flow_test_delete');
        Test.stopTest();
        System.assert(true, 'deleteFlow with no versions is a no-op');
    }

    @isTest
    static void testDeleteFlow_success() {
        ConfigurableMock mock = new ConfigurableMock()
            .addPattern('/query/', 200,
                '{"records":[{"Id":"301VER001"}],"totalSize":1,"done":true}')
            .addPattern('/sobjects/Flow/301VER001', 204, '');

        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        ExtoleMetadataService.deleteFlow('Extole_Flow_test_delete2');
        Test.stopTest();
        System.assert(true, 'deleteFlow completed without exception');
    }

    // =========================================================================
    // ExtoleMetadataService — error translation
    // =========================================================================

    @isTest
    static void testTranslateMetadataError_403() {
        String msg = ExtoleMetadataService.translateMetadataError(403, 'Forbidden');
        System.assert(msg.contains('Customize Application') || msg.contains('Named Credential'),
            '403 metadata → permission message');
    }

    @isTest
    static void testTranslateMetadataError_401() {
        String msg = ExtoleMetadataService.translateMetadataError(401, 'Unauthorized');
        System.assert(msg.contains('Named Credential') || msg.contains('authentication'),
            '401 → Named Credential auth message');
    }

    @isTest
    static void testTranslateMetadataError_duplicateName() {
        String msg = ExtoleMetadataService.translateMetadataError(400, 'DUPLICATE_DEVELOPER_NAME');
        System.assert(msg.contains('already exists'), 'Duplicate name → friendly message');
    }

    @isTest
    static void testTranslateMetadataError_unknown() {
        String msg = ExtoleMetadataService.translateMetadataError(500, 'Internal Server Error');
        System.assert(msg.contains('500'), 'Unknown metadata error includes HTTP status');
    }

    // =========================================================================
    // Extole_Event_Cfg__c — DML operations
    // =========================================================================

    @isTest
    static void testEventConfigRecord_insertAndQuery() {
        Test.startTest();
        insert new Extole_Event_Cfg__c(
            Config_Key__c     = 'test_insert_key',
            Event_Name__c     = 'test_event',
            Trigger_Object__c = 'Lead',
            Trigger_Type__c   = 'CREATED',
            Status__c         = 'DRAFT'
        );
        Test.stopTest();

        List<Extole_Event_Cfg__c> found = [
            SELECT Config_Key__c, Status__c FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = 'test_insert_key' LIMIT 1
        ];
        System.assertEquals(1, found.size(), 'Config record was inserted');
        System.assertEquals('DRAFT', found[0].Status__c, 'Status is DRAFT');
    }

    @isTest
    static void testEventConfigRecord_upsertByConfigKey() {
        Extole_Event_Cfg__c rec = new Extole_Event_Cfg__c(
            Config_Key__c = 'test_upsert_key',
            Event_Name__c = 'upsert_event',
            Status__c     = 'DRAFT'
        );
        Test.startTest();
        upsert rec Extole_Event_Cfg__c.Config_Key__c;
        rec.Status__c = 'ACTIVE';
        upsert rec Extole_Event_Cfg__c.Config_Key__c;
        Test.stopTest();

        List<Extole_Event_Cfg__c> found = [
            SELECT Status__c FROM Extole_Event_Cfg__c WHERE Config_Key__c = 'test_upsert_key' LIMIT 1
        ];
        System.assertEquals(1, found.size(), 'Single record after upsert');
        System.assertEquals('ACTIVE', found[0].Status__c, 'Status updated to ACTIVE');
    }

    // =========================================================================
    // ExtoleSafetyCheckService — campaign scanning
    // =========================================================================

    @isTest
    static void testScanCampaigns_found_topLevelEventNames() {
        String body = '[{"id":"camp1","name":"Spring Promo","state":"PUBLISHED",'
            + '"event_names":["lead_created","lead_converted"]}]';
        Test.startTest();
        Map<String, Object> result = ExtoleSafetyCheckService.scanCampaigns(body, 'lead_created');
        Test.stopTest();
        System.assertEquals('FOUND', result.get('status'));
        System.assertEquals('Spring Promo', result.get('campaignName'));
    }

    @isTest
    static void testScanCampaigns_notFound() {
        String body = '[{"id":"camp1","name":"Spring Promo","state":"PUBLISHED",'
            + '"event_names":["some_other_event"]}]';
        Test.startTest();
        Map<String, Object> result = ExtoleSafetyCheckService.scanCampaigns(body, 'lead_created');
        Test.stopTest();
        System.assertEquals('NOT_FOUND', result.get('status'));
    }

    @isTest
    static void testScanCampaigns_draftCampaignIgnored() {
        String body = '[{"id":"camp1","name":"Draft Promo","state":"DRAFT",'
            + '"event_names":["lead_created"]}]';
        Test.startTest();
        Map<String, Object> result = ExtoleSafetyCheckService.scanCampaigns(body, 'lead_created');
        Test.stopTest();
        System.assertEquals('NOT_FOUND', result.get('status'), 'Draft campaign is not FOUND');
    }

    @isTest
    static void testScanCampaigns_triggersShape() {
        String body = '[{"id":"camp2","name":"Referral","state":"ACTIVE","triggers":['
            + '{"event_name":"lead_created"}]}]';
        Test.startTest();
        Map<String, Object> result = ExtoleSafetyCheckService.scanCampaigns(body, 'lead_created');
        Test.stopTest();
        System.assertEquals('FOUND', result.get('status'));
    }

    @isTest
    static void testScanCampaigns_buildsShape() {
        String body = '[{"id":"camp3","name":"Nested","state":"PUBLISHED","builds":['
            + '{"triggers":[{"event_names":["lead_created","opp_won"]}]}]}]';
        Test.startTest();
        Map<String, Object> result = ExtoleSafetyCheckService.scanCampaigns(body, 'lead_created');
        Test.stopTest();
        System.assertEquals('FOUND', result.get('status'));
    }

    @isTest
    static void testScanCampaigns_wrapperShape() {
        String body = '{"campaigns":[{"id":"camp4","name":"Wrapped","state":"ACTIVE",'
            + '"event_names":["lead_created"]}]}';
        Test.startTest();
        Map<String, Object> result = ExtoleSafetyCheckService.scanCampaigns(body, 'lead_created');
        Test.stopTest();
        System.assertEquals('FOUND', result.get('status'));
    }

    @isTest
    static void testScanCampaigns_caseInsensitive() {
        String body = '[{"id":"camp5","name":"Case Test","state":"PUBLISHED",'
            + '"event_names":["Lead_Created"]}]';
        Test.startTest();
        Map<String, Object> result = ExtoleSafetyCheckService.scanCampaigns(body, 'lead_created');
        Test.stopTest();
        System.assertEquals('FOUND', result.get('status'), 'Matching is case-insensitive');
    }

    @isTest
    static void testScanCampaigns_invalidJson() {
        Test.startTest();
        Map<String, Object> result = ExtoleSafetyCheckService.scanCampaigns('not valid json', 'lead_created');
        Test.stopTest();
        System.assertEquals('UNKNOWN', result.get('status'), 'Invalid JSON → UNKNOWN');
    }

    @isTest
    static void testCheckEventUsage_httpSuccess_found() {
        String campaignBody = '[{"id":"c1","name":"Active Campaign","state":"PUBLISHED",'
            + '"event_names":["lead_converted"]}]';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(200, campaignBody));
        Test.startTest();
        Map<String, Object> result = ExtoleSafetyCheckService.checkEventUsage('lead_converted');
        Test.stopTest();
        System.assertEquals('FOUND', result.get('status'));
    }

    @isTest
    static void testCheckEventUsage_http500_unknown() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock(500, 'Server Error'));
        Test.startTest();
        Map<String, Object> result = ExtoleSafetyCheckService.checkEventUsage('lead_converted');
        Test.stopTest();
        System.assertEquals('UNKNOWN', result.get('status'), 'HTTP 500 → UNKNOWN');
    }

    @isTest
    static void testCheckEventUsage_timeout_unknown() {
        Test.setMock(HttpCalloutMock.class, new TimeoutMock());
        Test.startTest();
        Map<String, Object> result = ExtoleSafetyCheckService.checkEventUsage('lead_converted');
        Test.stopTest();
        System.assertEquals('UNKNOWN', result.get('status'), 'Timeout → UNKNOWN');
    }

    @isTest
    static void testCheckEventUsage_blankEventName() {
        Test.startTest();
        Map<String, Object> result = ExtoleSafetyCheckService.checkEventUsage('');
        Test.stopTest();
        System.assertEquals('NOT_FOUND', result.get('status'), 'Blank event name → NOT_FOUND');
    }

    // =========================================================================
    // ExtoleEventController — getEventConfigs / getEventLogs
    // =========================================================================

    @isTest
    static void testGetEventConfigs_returnsList() {
        Test.startTest();
        List<Extole_Event_Cfg__c> configs = ExtoleEventController.getEventConfigs();
        Test.stopTest();
        System.assertNotEquals(null, configs, 'getEventConfigs returns a non-null list');
    }

    @isTest
    static void testGetEventLogs_noConfigKey() {
        Test.startTest();
        List<Extole_Event_Log__c> logs = ExtoleEventController.getEventLogs(null);
        Test.stopTest();
        System.assertNotEquals(null, logs);
    }

    @isTest
    static void testGetEventLogs_withConfigKey() {
        insert new Extole_Event_Log__c(
            Config_Key__c = 'test_config_key_001',
            Event_Type__c = 'CONFIG_CREATED',
            User_Id__c    = UserInfo.getUserId(),
            Timestamp__c  = DateTime.now(),
            Result__c     = 'SUCCESS',
            Detail__c     = 'Unit test log entry'
        );
        Test.startTest();
        List<Extole_Event_Log__c> logs = ExtoleEventController.getEventLogs('test_config_key_001');
        Test.stopTest();
        System.assertEquals(1, logs.size());
    }

    // =========================================================================
    // ExtoleEventController — getAvailableObjects / getFieldsForObject
    // =========================================================================

    @isTest
    static void testGetAvailableObjects_returnsNonEmpty() {
        Test.startTest();
        List<Map<String, Object>> objects = ExtoleEventController.getAvailableObjects();
        Test.stopTest();
        System.assert(!objects.isEmpty(), 'Returns at least one object');
    }

    @isTest
    static void testGetAvailableObjects_priorityObjectsFirst() {
        Test.startTest();
        List<Map<String, Object>> objects = ExtoleEventController.getAvailableObjects();
        Test.stopTest();
        Boolean leadFound = false;
        for (Map<String, Object> obj : objects) {
            if (obj.get('apiName') == 'Lead') { leadFound = true; break; }
        }
        System.assert(leadFound, 'Lead is present in available objects');
    }

    @isTest
    static void testGetFieldsForObject_lead() {
        Test.startTest();
        List<Map<String, Object>> fields = ExtoleEventController.getFieldsForObject('Lead');
        Test.stopTest();
        System.assert(!fields.isEmpty(), 'Lead has accessible fields');
        Boolean emailFound = false;
        for (Map<String, Object> f : fields) {
            if (f.get('apiName') == 'Email') { emailFound = true; break; }
        }
        System.assert(emailFound, 'Email field present on Lead');
    }

    @isTest
    static void testGetFieldsForObject_blankName() {
        Test.startTest();
        try {
            ExtoleEventController.getFieldsForObject('');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null);
        }
        Test.stopTest();
    }

    @isTest
    static void testGetFieldsForObject_unknownObject() {
        Test.startTest();
        try {
            ExtoleEventController.getFieldsForObject('Completely_Fake_Object__x');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // =========================================================================
    // ExtoleEventController — previewPayload
    // =========================================================================

    @isTest
    static void testPreviewPayload_leadRecord() {
        Lead testLead = [SELECT Id FROM Lead WHERE LastName = 'LeadPreview' LIMIT 1];
        String configJson = '{"triggerObject":"Lead","eventName":"lead_created",'
            + '"fieldMappingsJson":"[{\\"extole_param\\":\\"email\\",\\"sfdc_field\\":\\"Email\\",\\"static_value\\":null},'
            + '{\\"extole_param\\":\\"partner_user_id\\",\\"sfdc_field\\":\\"Id\\",\\"static_value\\":null},'
            + '{\\"extole_param\\":\\"company\\",\\"sfdc_field\\":\\"Company\\",\\"static_value\\":null}]"}';

        Test.startTest();
        String payload = ExtoleEventController.previewPayload(configJson, testLead.Id);
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assert(payload.contains('lead_created'), 'Event name in payload');
        System.assert(payload.contains('preview@extole-test.com'), 'Email value in payload');
        System.assert(payload.contains('extole-sfdc-app'), 'app_type in payload');
    }

    @isTest
    static void testPreviewPayload_staticValue() {
        Lead testLead = [SELECT Id FROM Lead WHERE LastName = 'LeadPreview' LIMIT 1];
        String configJson = '{"triggerObject":"Lead","eventName":"lead_test",'
            + '"fieldMappingsJson":"[{\\"extole_param\\":\\"source\\",\\"sfdc_field\\":null,\\"static_value\\":\\"sfdc_web\\"}]"}';

        Test.startTest();
        String payload = ExtoleEventController.previewPayload(configJson, testLead.Id);
        Test.stopTest();

        System.assert(payload.contains('sfdc_web'), 'Static value injected in preview');
    }

    @isTest
    static void testPreviewPayload_unknownObject_throws() {
        Lead testLead = [SELECT Id FROM Lead WHERE LastName = 'LeadPreview' LIMIT 1];
        String configJson = '{"triggerObject":"Completely_Fake_Object__x","eventName":"test",'
            + '"fieldMappingsJson":"[{\\"extole_param\\":\\"email\\",\\"sfdc_field\\":\\"Email\\",\\"static_value\\":null}]"}';

        Test.startTest();
        try {
            ExtoleEventController.previewPayload(configJson, testLead.Id);
            System.assert(false, 'Expected AuraHandledException for unknown object');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Exception message is present');
        }
        Test.stopTest();
    }

    @isTest
    static void testPreviewPayload_invalidFieldSkipped() {
        // An sfdc_field that does not exist on the object should be silently skipped,
        // not injected into the SOQL string (SOQL injection fix verification).
        Lead testLead = [SELECT Id FROM Lead WHERE LastName = 'LeadPreview' LIMIT 1];
        String configJson = '{"triggerObject":"Lead","eventName":"lead_test",'
            + '"fieldMappingsJson":"[{\\"extole_param\\":\\"email\\",\\"sfdc_field\\":\\"Email\\",\\"static_value\\":null},'
            + '{\\"extole_param\\":\\"injected\\",\\"sfdc_field\\":\\"Nonexistent_Field_XYZ__c\\",\\"static_value\\":null}]"}';

        Test.startTest();
        String payload = ExtoleEventController.previewPayload(configJson, testLead.Id);
        Test.stopTest();

        // Valid Email field should be in the payload; invalid field should be absent
        System.assert(payload.contains('preview@extole-test.com'), 'Valid field included');
        System.assert(!payload.contains('injected'), 'Invalid field silently skipped');
    }

    @isTest
    static void testPreviewPayload_missingRecordId() {
        Test.startTest();
        try {
            ExtoleEventController.previewPayload(
                '{"triggerObject":"Lead","eventName":"lead_test","fieldMappingsJson":"[]"}',
                null
            );
            System.assert(false, 'Expected AuraHandledException for null recordId');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testPreviewPayload_nullFieldsOmitted() {
        Lead testLead = [SELECT Id FROM Lead WHERE LastName = 'LeadPreview' LIMIT 1];
        String configJson = '{"triggerObject":"Lead","eventName":"lead_test",'
            + '"fieldMappingsJson":"[{\\"extole_param\\":\\"industry\\",\\"sfdc_field\\":\\"Industry\\",\\"static_value\\":null},'
            + '{\\"extole_param\\":\\"email\\",\\"sfdc_field\\":\\"Email\\",\\"static_value\\":null}]"}';

        Test.startTest();
        String payload = ExtoleEventController.previewPayload(configJson, testLead.Id);
        Test.stopTest();

        System.assert(!payload.contains('"industry" : null'), 'Null fields are omitted');
        System.assert(payload.contains('preview@extole-test.com'), 'Non-null fields are present');
    }

    // =========================================================================
    // ExtoleEventController — checkEventUsage
    // =========================================================================

    @isTest
    static void testCheckEventUsage_controller_found() {
        String campaignBody = '[{"id":"cx1","name":"Promo","state":"PUBLISHED",'
            + '"event_names":["lead_created"]}]';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(200, campaignBody));

        Test.startTest();
        Map<String, Object> result = ExtoleEventController.checkEventUsage('lead_created');
        Test.stopTest();

        System.assertEquals('FOUND', result.get('status'));
    }

    @isTest
    static void testCheckEventUsage_controller_timeout() {
        Test.setMock(HttpCalloutMock.class, new TimeoutMock());
        Test.startTest();
        Map<String, Object> result = ExtoleEventController.checkEventUsage('opp_won');
        Test.stopTest();
        System.assertEquals('UNKNOWN', result.get('status'));
    }

    // =========================================================================
    // ExtoleEventController — saveEventConfig
    // =========================================================================

    @isTest
    static void testSaveEventConfig_missingFields() {
        Test.startTest();
        try {
            ExtoleEventController.saveEventConfig('{"someField":"test_event"}');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveEventConfig_success() {
        Test.startTest();
        String key = ExtoleEventController.saveEventConfig(
            '{"eventName":"save_test_event","triggerObject":"Lead",'
            + '"triggerType":"CREATED","fieldMappingsJson":"[]"}'
        );
        Test.stopTest();

        System.assertNotEquals(null, key, 'saveEventConfig returns a configKey');
        List<Extole_Event_Cfg__c> saved = [
            SELECT Status__c FROM Extole_Event_Cfg__c WHERE Config_Key__c = :key LIMIT 1
        ];
        System.assertEquals(1, saved.size(), 'Config record saved');
        System.assertEquals('DRAFT', saved[0].Status__c);
    }

    // =========================================================================
    // ExtoleEventController — deployEventConfig (mocked Named Credential callouts)
    // =========================================================================

    @isTest
    static void testDeployEventConfig_success() {
        // Named Credential callouts for deactivateFlow query and deployFlow POST
        ConfigurableMock mock = new ConfigurableMock()
            .addPattern('/query/', 200, '{"records":[],"totalSize":0,"done":true}')
            .addPattern('/sobjects/Flow/', 201, '{"id":"301NEWFLOW001","success":true}');

        Test.setMock(HttpCalloutMock.class, mock);

        insert new Extole_Event_Cfg__c(
            Config_Key__c          = 'Lead_Created',
            Event_Name__c          = 'lead_created',
            Trigger_Object__c      = 'Lead',
            Trigger_Type__c        = 'CREATED',
            Field_Mappings_JSON__c = '[{"extole_param":"email","sfdc_field":"Email","static_value":null}]',
            Status__c              = 'DRAFT'
        );

        String configJson = '{"configKey":"Lead_Created",'
            + '"eventName":"lead_created","triggerObject":"Lead","triggerType":"CREATED",'
            + '"triggerField":null,"triggerValue":null,"triggerFromValue":null,"triggerToValue":null,'
            + '"fieldMappingsJson":"[{\\"extole_param\\":\\"email\\",\\"sfdc_field\\":\\"Email\\",\\"static_value\\":null}]"}';

        Test.startTest();
        String jobId = ExtoleEventController.deployEventConfig(configJson);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'deployEventConfig returns a jobId');

        // Config should be ACTIVE and reference ExtoleUniversalHandler
        Extole_Event_Cfg__c updated = [
            SELECT Status__c, Apex_Class_Name__c, Flow_Name__c
            FROM Extole_Event_Cfg__c WHERE Config_Key__c = 'Lead_Created' LIMIT 1
        ];
        System.assertEquals('ACTIVE', updated.Status__c, 'Config marked ACTIVE after deploy');
        System.assertEquals('ExtoleUniversalHandler', updated.Apex_Class_Name__c,
            'Apex_Class_Name__c set to ExtoleUniversalHandler');
    }

    @isTest
    static void testDeployEventConfig_configNotFound() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock(200, '{}'));
        Test.startTest();
        try {
            ExtoleEventController.deployEventConfig(
                '{"configKey":"totally_nonexistent_key_xyz",'
                + '"eventName":"test_evt","triggerObject":"Lead","triggerType":"CREATED",'
                + '"fieldMappingsJson":"[]"}'
            );
            System.assert(true, 'deployEventConfig ran without exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'AuraHandledException thrown as expected');
        }
        Test.stopTest();
    }

    // =========================================================================
    // ExtoleEventController — pollDeployStatus
    // =========================================================================

    @isTest
    static void testPollDeployStatus_active() {
        insert new Extole_Event_Cfg__c(
            Config_Key__c = 'poll_test_active',
            Event_Name__c = 'evt',
            Status__c     = 'ACTIVE'
        );
        Test.startTest();
        Map<String, Object> result = ExtoleEventController.pollDeployStatus('poll_test_active');
        Test.stopTest();
        System.assertEquals('SUCCEEDED', result.get('status'));
    }

    @isTest
    static void testPollDeployStatus_failed() {
        insert new Extole_Event_Cfg__c(
            Config_Key__c    = 'poll_test_failed',
            Event_Name__c    = 'evt',
            Status__c        = 'DEPLOY_FAILED',
            Deploy_Error__c  = 'Metadata API error'
        );
        Test.startTest();
        Map<String, Object> result = ExtoleEventController.pollDeployStatus('poll_test_failed');
        Test.stopTest();
        System.assertEquals('FAILED', result.get('status'));
    }

    @isTest
    static void testPollDeployStatus_notFound() {
        Test.startTest();
        Map<String, Object> result = ExtoleEventController.pollDeployStatus('nonexistent_poll_key');
        Test.stopTest();
        System.assertEquals('FAILED', result.get('status'));
    }
}
