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
}
