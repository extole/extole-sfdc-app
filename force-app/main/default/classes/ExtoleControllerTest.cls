@IsTest
private class ExtoleControllerTest {
    @IsTest
    static void testGetCurrentUserTimezone() {
        Test.startTest();
        String tz = ExtoleController.getCurrentUserTimezone();
        Test.stopTest();
        System.assert(String.isNotBlank(tz));
    }

    @IsTest
    static void testGetDebugLogsAndClear() {
        insert new Extole_Debug_Log__c(
            Report_Name__c = 'x',
            Event_Type__c = 'INFO',
            Detail__c = 'hi',
            Log_Timestamp__c = DateTime.now()
        );

        Test.startTest();
        List<Extole_Debug_Log__c> logs = ExtoleController.getDebugLogs();
        System.assertEquals(1, logs.size());

        Integer cleared = ExtoleController.clearDebugLogs();
        Test.stopTest();

        System.assertEquals(1, cleared);
        System.assertEquals(0, [SELECT COUNT() FROM Extole_Debug_Log__c]);
    }

    @IsTest
    static void testClearSyncLogs() {
        insert new Extole_Sync_Log__c(
            Report_Name__c = 'x',
            Status__c = 'SUCCESS',
            Sync_Timestamp__c = DateTime.now()
        );

        Test.startTest();
        ExtoleController.clearSyncLogs();
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Extole_Sync_Log__c]);
    }

    @IsTest
    static void testGetScheduleStatus_noSettings() {
        Test.startTest();
        Map<String, Object> result = ExtoleController.getScheduleStatus();
        Test.stopTest();

        System.assertEquals('', result.get('cadence'));
    }

    @IsTest
    static void testGetScheduleStatus_settingsWithoutActiveJob() {
        Extole_App_Settings__c settings = new Extole_App_Settings__c();
        settings.Sync_Cadence__c = 'Daily';
        upsert settings;

        Test.startTest();
        Map<String, Object> result = ExtoleController.getScheduleStatus();
        Test.stopTest();

        System.assertEquals('Daily', result.get('cadence'));
    }

    @IsTest
    static void testGetScheduleStatus_withActiveJob() {
        Test.startTest();
        ExtoleSyncJob.scheduleJob('Nightly');
        Map<String, Object> result = ExtoleController.getScheduleStatus();
        Test.stopTest();

        System.assertEquals(true, result.get('isScheduled'));
    }

    private class SequentialMock implements HttpCalloutMock {
        List<HttpResponse> responses;
        Integer callIndex = 0;
        SequentialMock(List<HttpResponse> responses) {
            this.responses = responses;
        }
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = responses[
                Math.min(callIndex, responses.size() - 1)
            ];
            callIndex++;
            return response;
        }
    }

    private static HttpResponse mockResponse(Integer status, String body) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(status);
        response.setBody(body);
        return response;
    }

    @IsTest
    static void testGetReportColumns_latestIsDone() {
        Test.setMock(
            HttpCalloutMock.class,
            new SequentialMock(
                new List<HttpResponse>{
                    mockResponse(200, '{"status":"DONE","report_id":"rpt1"}'),
                    mockResponse(200, '[{"col_b":"2","col_a":"1"}]')
                }
            )
        );

        Test.startTest();
        List<String> columns = ExtoleController.getReportColumns('runner-1');
        Test.stopTest();

        System.assertEquals(new List<String>{ 'col_a', 'col_b' }, columns);
    }

    @IsTest
    static void testGetReportColumns_fallsBackToReportsListWhenLatestNotDone() {
        Test.setMock(
            HttpCalloutMock.class,
            new SequentialMock(
                new List<HttpResponse>{
                    mockResponse(200, '{"status":"PENDING"}'),
                    mockResponse(
                        200,
                        '[{"status":"FAILED","id":"bad"},{"status":"DONE","report_id":"rpt2"}]'
                    ),
                    mockResponse(200, '[{"col1":"x"}]')
                }
            )
        );

        Test.startTest();
        List<String> columns = ExtoleController.getReportColumns('runner-2');
        Test.stopTest();

        System.assertEquals(new List<String>{ 'col1' }, columns);
    }

    @IsTest
    static void testGetReportColumns_noCompletedReportThrows() {
        Test.setMock(
            HttpCalloutMock.class,
            new SequentialMock(
                new List<HttpResponse>{
                    mockResponse(200, '{"status":"PENDING"}'),
                    mockResponse(200, '[]')
                }
            )
        );

        Boolean threw = false;
        Test.startTest();
        try {
            ExtoleController.getReportColumns('runner-3');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetReportColumns_downloadFailureThrows() {
        Test.setMock(
            HttpCalloutMock.class,
            new SequentialMock(
                new List<HttpResponse>{
                    mockResponse(200, '{"status":"DONE","report_id":"rpt1"}'),
                    mockResponse(500, '{"error":"boom"}')
                }
            )
        );

        Boolean threw = false;
        Test.startTest();
        try {
            ExtoleController.getReportColumns('runner-4');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetReportColumns_emptyRowsReturnsEmptyList() {
        Test.setMock(
            HttpCalloutMock.class,
            new SequentialMock(
                new List<HttpResponse>{
                    mockResponse(200, '{"status":"DONE","report_id":"rpt1"}'),
                    mockResponse(200, '[]')
                }
            )
        );

        Test.startTest();
        List<String> columns = ExtoleController.getReportColumns('runner-5');
        Test.stopTest();

        System.assertEquals(0, columns.size());
    }

    @IsTest
    static void testGetObjectFields_contactIncludesAccountNameVirtualField() {
        Test.startTest();
        List<Map<String, String>> fields = ExtoleController.getObjectFields(
            'Contact'
        );
        Test.stopTest();

        Boolean foundAccountName = false, foundEmail = false;
        for (Map<String, String> f : fields) {
            if (f.get('value') == 'Account.Name')
                foundAccountName = true;
            if (f.get('value') == 'Email')
                foundEmail = true;
        }
        System.assertEquals(true, foundAccountName);
        System.assertEquals(true, foundEmail);
    }

    @IsTest
    static void testGetObjectFields_unknownObjectReturnsEmpty() {
        Test.startTest();
        List<Map<String, String>> fields = ExtoleController.getObjectFields(
            'NotARealObject__x'
        );
        Test.stopTest();

        System.assertEquals(0, fields.size());
    }

    @IsTest
    static void testGetFieldValues_picklistReturnsActiveEntries() {
        Test.startTest();
        List<String> values = ExtoleController.getFieldValues(
            'Lead',
            'LeadSource'
        );
        Test.stopTest();

        System.assert(values.size() > 0);
    }

    @IsTest
    static void testGetFieldValues_unknownFieldReturnsEmpty() {
        Test.startTest();
        List<String> values = ExtoleController.getFieldValues(
            'Contact',
            'not_a_real_field__x'
        );
        Test.stopTest();

        System.assertEquals(0, values.size());
    }

    @IsTest
    static void testGetFieldValues_unknownObjectReturnsEmpty() {
        Test.startTest();
        List<String> values = ExtoleController.getFieldValues(
            'NotARealObject__x',
            'Name'
        );
        Test.stopTest();

        System.assertEquals(0, values.size());
    }

    @IsTest
    static void testGetFieldValues_textFieldReturnsDistinctValues() {
        insert new Contact(LastName = 'A', Department = 'Engineering');
        insert new Contact(LastName = 'B', Department = 'Engineering');
        insert new Contact(LastName = 'C', Department = 'Sales');

        Test.startTest();
        List<String> values = ExtoleController.getFieldValues(
            'Contact',
            'Department'
        );
        Test.stopTest();

        System.assert(values.contains('Engineering'));
        System.assert(values.contains('Sales'));
    }

    @IsTest
    static void testGetAttributedLeads_noSettingsReturnsUnconfigured() {
        Test.startTest();
        Map<String, Object> result = ExtoleController.getAttributedLeads();
        Test.stopTest();

        System.assertEquals(false, result.get('configured'));
    }

    @IsTest
    static void testGetAttributedLeads_invalidFieldReturnsError() {
        Extole_App_Settings__c settings = new Extole_App_Settings__c(
            List_View_Object__c = 'Contact',
            List_View_Field__c = 'not_a_real_field__x',
            List_View_Value__c = 'Web'
        );
        upsert settings;

        Test.startTest();
        Map<String, Object> result = ExtoleController.getAttributedLeads();
        Test.stopTest();

        System.assertNotEquals(null, result.get('error'));
    }

    @IsTest
    static void testGetAttributedLeads_happyPathReturnsMatchingRecords() {
        Account acct = new Account(Name = 'Acme Corp');
        insert acct;
        insert new Contact(
            LastName = 'Match1',
            LeadSource = 'Web',
            AccountId = acct.Id
        );
        insert new Contact(
            LastName = 'Match2',
            LeadSource = 'Web',
            AccountId = acct.Id
        );
        insert new Contact(LastName = 'NoMatch', LeadSource = 'Phone Inquiry');

        Extole_App_Settings__c settings = new Extole_App_Settings__c(
            List_View_Object__c = 'Contact',
            List_View_Field__c = 'LeadSource',
            List_View_Value__c = 'Web',
            List_View_Columns__c = 'Account.Name,Email'
        );
        upsert settings;

        Test.startTest();
        Map<String, Object> result = ExtoleController.getAttributedLeads();
        Test.stopTest();

        System.assertEquals(true, result.get('configured'));
        System.assertEquals('Contact', result.get('objectType'));
        System.assertEquals(2, result.get('totalCount'));
        List<Object> records = (List<Object>) result.get('records');
        System.assertEquals(2, records.size());
        List<Object> extraColumns = (List<Object>) result.get('extraColumns');
        System.assert(extraColumns.size() > 0);
    }
}
