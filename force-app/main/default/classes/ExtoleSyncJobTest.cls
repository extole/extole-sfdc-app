@IsTest
private class ExtoleSyncJobTest {

    // ─────────────────────────────────────────────────────────────────────────
    // HTTP mock: simulates the Extole API
    // ─────────────────────────────────────────────────────────────────────────

    private class ExtoleMock implements HttpCalloutMock {
        // Tracks calls so tests can assert sequence
        public Integer callCount = 0;

        public HTTPResponse respond(HTTPRequest req) {
            callCount++;
            String endpoint = req.getEndpoint();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            // POST /v4/reports  → trigger report
            if (endpoint.contains('/v4/reports') && req.getMethod() == 'POST') {
                res.setBody('{"report_id":"rpt-001","status":"PROCESSING","view_url":"https://my.extole.com/reports/view?id=rpt-001","client_id":"cli-999"}');
                return res;
            }

            // GET /v4/reports/rpt-001/download  → CSV-style JSON array
            if (endpoint.endsWith('/download')) {
                res.setBody('[{"week":"2024-01-01","referrals":"42"},{"week":"2024-01-08","referrals":"55"}]');
                return res;
            }

            // GET /v4/reports/rpt-001  → poll
            if (endpoint.contains('/v4/reports/rpt-001')) {
                res.setBody('{"id":"rpt-001","status":"DONE","view_url":"https://my.extole.com/reports/view?id=rpt-001","client_id":"cli-999"}');
                return res;
            }

            // GET /v6/report-types  → testConnection / getReportTypes
            if (endpoint.contains('/v6/report-types')) {
                res.setBody('[{"name":"referral_overview","display_name":"Referral Overview","executor_type":"SQL","formats":["JSON","CSV"]},'
                    + '{"name":"share_events","display_name":"Share Events","executor_type":"SPARK","formats":["JSON"]},'
                    + '{"name":"conversion_report","display_name":"Conversion Report","executor_type":"CONFIGURED","formats":["JSON"]}]');
                return res;
            }

            // Default fallback
            res.setStatusCode(404);
            res.setBody('{"error":"not found"}');
            return res;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test data helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static Extole_Report_Config__c makeConfig(String name, String execType) {
        Extole_Report_Config__c c = new Extole_Report_Config__c();
        c.Name              = name;
        c.Report_Name__c    = name;
        c.Report_Type__c    = execType;
        c.Executor_Type__c  = execType;
        c.Display_Label__c  = name;
        c.Value_Column__c   = 'referrals';
        c.Aggregation__c    = 'FIRST_ROW';
        c.Chart_Type__c     = 'None';
        c.Data_Mode__c      = 'Single Value';
        c.Date_Range__c     = 'Rolling 30';
        c.Display_Order__c  = 1;
        c.Active__c         = true;
        return c;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testSyncJobNoConfigs() {
        // With no configs, performSync should complete without error
        Test.setMock(HttpCalloutMock.class, new ExtoleMock());
        Test.startTest();
        ExtoleSyncJob.performSync();
        Test.stopTest();
        // No assertions needed — just verifying no exception thrown
        System.assert(true, 'performSync with no active configs should not throw');
    }

    @IsTest
    static void testSyncJobSingleConfig() {
        Extole_Report_Config__c config = makeConfig('referral_overview', 'SQL');
        insert config;

        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtoleSyncJob.performSync();
        Test.stopTest();

        // Verify snapshot created for all 3 date ranges
        List<Extole_Report_Snapshot__c> snaps = [
            SELECT Id, Value__c, Date_Range__c, Config_Status__c, Config_Id__c
            FROM Extole_Report_Snapshot__c
            WHERE Config_Id__c = :config.Id
        ];
        System.assertEquals(3, snaps.size(), 'Should have 3 snapshots (one per date range)');

        for (Extole_Report_Snapshot__c snap : snaps) {
            System.assertEquals('ACTIVE', snap.Config_Status__c, 'Snapshot should be ACTIVE');
            System.assertEquals('42', snap.Value__c, 'Extracted value should be 42');
        }

        // Verify sync logs written
        List<Extole_Sync_Log__c> logs = [
            SELECT Status__c, Report_Name__c FROM Extole_Sync_Log__c
            WHERE Report_Name__c = 'referral_overview'
        ];
        System.assertEquals(3, logs.size(), 'Should have 3 sync log entries');
        for (Extole_Sync_Log__c log : logs) {
            System.assertEquals('SUCCESS', log.Status__c, 'Sync log should be SUCCESS');
        }
    }

    @IsTest
    static void testSyncJobOrphanReconciliation() {
        // Create a snapshot with a fake (but valid-length) config ID to simulate an orphan.
        // Config_Id__c is a text field limited to 18 chars (Salesforce ID format).
        Extole_Report_Snapshot__c orphan = new Extole_Report_Snapshot__c();
        orphan.Name             = 'Orphaned Snapshot – Rolling 30';
        orphan.Config_Id__c     = 'a00000000000000001';  // 18-char fake ID
        orphan.Date_Range__c    = 'Rolling 30';
        orphan.Config_Status__c = 'ACTIVE';
        orphan.Value__c         = '999';
        insert orphan;

        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtoleSyncJob.performSync();
        Test.stopTest();

        // Verify orphan was marked ORPHANED
        Extole_Report_Snapshot__c updated = [
            SELECT Config_Status__c FROM Extole_Report_Snapshot__c WHERE Id = :orphan.Id
        ];
        System.assertEquals('ORPHANED', updated.Config_Status__c, 'Orphaned snapshot should be marked ORPHANED');
    }

    @IsTest
    static void testSyncJobTimeSeriesConfig() {
        Extole_Report_Config__c config = makeConfig('referral_timeseries', 'SQL');
        config.Data_Mode__c  = 'Time Series';
        config.Chart_Type__c = 'Sparkline';
        insert config;

        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtoleSyncJob.performSync();
        Test.stopTest();

        List<Extole_Report_Snapshot__c> snaps = [
            SELECT Time_Series_JSON__c, Prior_Period_Value__c
            FROM Extole_Report_Snapshot__c
            WHERE Config_Id__c = :config.Id
            LIMIT 1
        ];
        System.assert(!snaps.isEmpty(), 'Should have snapshot for time series config');
        System.assertNotEquals(null, snaps[0].Time_Series_JSON__c,
            'Time series JSON should be populated');
    }

    @IsTest
    static void testSyncJobDebugLogging() {
        // Enable debug logging in settings
        Extole_App_Settings__c settings = Extole_App_Settings__c.getOrgDefaults();
        if (settings == null) settings = new Extole_App_Settings__c();
        settings.Debug_Logging_Enabled__c = true;
        upsert settings;

        Extole_Report_Config__c config = makeConfig('debug_report', 'CONFIGURED');
        insert config;

        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtoleSyncJob.performSync();
        Test.stopTest();

        List<Extole_Debug_Log__c> debugLogs = [
            SELECT Event_Type__c FROM Extole_Debug_Log__c
            WHERE Report_Name__c = 'debug_report'
        ];
        System.assert(!debugLogs.isEmpty(), 'Debug logs should be written when debug logging enabled');

        // Verify RAW_OUTPUT was captured
        Boolean hasRawOutput = false;
        for (Extole_Debug_Log__c dl : debugLogs) {
            if (dl.Event_Type__c == 'RAW_OUTPUT') {
                hasRawOutput = true;
                break;
            }
        }
        System.assert(hasRawOutput, 'Should have a RAW_OUTPUT debug log entry');
    }

    @IsTest
    static void testExtoleControllerGetSnapshots() {
        // Insert a snapshot record so the SOQL query has something to return
        Extole_Report_Snapshot__c snap = new Extole_Report_Snapshot__c();
        snap.Name            = 'Test Snapshot – Rolling 30';
        snap.Value__c        = '100';
        snap.Date_Range__c   = 'Rolling 30';
        snap.Config_Id__c    = 'abc123';
        snap.Config_Status__c = 'ACTIVE';
        insert snap;

        List<Extole_Report_Snapshot__c> result = ExtoleController.getSnapshots();
        System.assert(!result.isEmpty(), 'getSnapshots should return records');
    }

    @IsTest
    static void testExtoleControllerGetConfigs() {
        Extole_Report_Config__c config = makeConfig('test_config', 'SQL');
        insert config;

        List<Extole_Report_Config__c> result = ExtoleController.getConfigs();
        System.assert(!result.isEmpty(), 'getConfigs should return records');
    }

    @IsTest
    static void testExtoleControllerSaveAndDeleteConfig() {
        Extole_Report_Config__c config = makeConfig('save_delete_test', 'SQL');
        Id savedId = ExtoleController.saveConfig(config);
        System.assertNotEquals(null, savedId, 'saveConfig should return an Id');

        // Update it
        config.Display_Label__c = 'Updated Label';
        ExtoleController.saveConfig(config);

        Extole_Report_Config__c fetched = [SELECT Display_Label__c FROM Extole_Report_Config__c WHERE Id = :savedId];
        System.assertEquals('Updated Label', fetched.Display_Label__c, 'Display label should be updated');

        // Delete it
        ExtoleController.deleteConfig(savedId);
        List<Extole_Report_Config__c> remaining = [SELECT Id FROM Extole_Report_Config__c WHERE Id = :savedId];
        System.assert(remaining.isEmpty(), 'Config should be deleted');
    }

    @IsTest
    static void testExtoleControllerGetAndSaveSettings() {
        Extole_App_Settings__c settings = ExtoleController.getSettings();
        System.assertNotEquals(null, settings, 'getSettings should always return a non-null object');

        settings.Debug_Logging_Enabled__c = true;
        settings.Sync_Cadence__c = 'Nightly';
        ExtoleController.saveSettings(settings);

        Extole_App_Settings__c saved = Extole_App_Settings__c.getOrgDefaults();
        System.assertEquals(true, saved.Debug_Logging_Enabled__c, 'Debug logging should be saved');
    }

    @IsTest
    static void testExtoleControllerTestConnection() {
        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = ExtoleController.testConnection();
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'testConnection should return success=true');
        System.assertEquals(3, (Integer) result.get('reportCount'), 'Should return 3 mock report types');
    }

    @IsTest
    static void testExtoleControllerGetReportTypes() {
        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String rawJson = ExtoleController.getReportTypes();
        Test.stopTest();

        System.assertNotEquals(null, rawJson, 'getReportTypes should return JSON string');
        System.assert(rawJson.contains('referral_overview'), 'Should contain report type name');
    }

    @IsTest
    static void testExtoleControllerTriggerSingleSync() {
        Extole_Report_Config__c config = makeConfig('single_sync_test', 'SQL');
        insert config;

        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = ExtoleController.triggerSingleSync(config.Id);
        Test.stopTest();

        System.assertEquals('SUCCESS', result.get('status'), 'triggerSingleSync should return SUCCESS');
        System.assertEquals('42', result.get('value'), 'Extracted value should be 42');
    }

    @IsTest
    static void testExtoleControllerClearOrphanedSnapshots() {
        // Insert orphaned snapshots
        List<Extole_Report_Snapshot__c> orphans = new List<Extole_Report_Snapshot__c>();
        for (Integer i = 0; i < 3; i++) {
            Extole_Report_Snapshot__c s = new Extole_Report_Snapshot__c();
            s.Name             = 'Orphan ' + i + ' – Rolling 30';
            s.Config_Id__c     = 'orphan-config-' + i;
            s.Date_Range__c    = 'Rolling 30';
            s.Config_Status__c = 'ORPHANED';
            orphans.add(s);
        }
        insert orphans;

        Integer count = ExtoleController.clearOrphanedSnapshots();
        System.assertEquals(3, count, 'Should have deleted 3 orphaned snapshots');
    }

    @IsTest
    static void testExtoleControllerClearDebugLogs() {
        // Insert debug log records
        List<Extole_Debug_Log__c> logs = new List<Extole_Debug_Log__c>();
        for (Integer i = 0; i < 5; i++) {
            Extole_Debug_Log__c dl = new Extole_Debug_Log__c();
            dl.Report_Name__c   = 'test_report';
            dl.Log_Timestamp__c = System.now();
            dl.Event_Type__c    = 'HTTP_REQUEST';
            dl.Detail__c        = 'Test detail ' + i;
            dl.Sync_Batch_Id__c = 'batch-001';
            logs.add(dl);
        }
        insert logs;

        Integer count = ExtoleController.clearDebugLogs();
        System.assertEquals(5, count, 'Should have deleted 5 debug log entries');
    }

    @IsTest
    static void testExtoleControllerGetSyncLogs() {
        // Insert a sync log record
        Extole_Sync_Log__c log = new Extole_Sync_Log__c();
        log.Report_Name__c    = 'test_report';
        log.Date_Range__c     = 'Rolling 30';
        log.Executor_Type__c  = 'SQL';
        log.Status__c         = 'SUCCESS';
        log.Sync_Timestamp__c = System.now();
        log.Sync_Batch_Id__c  = 'batch-001';
        insert log;

        List<Extole_Sync_Log__c> result = ExtoleController.getSyncLogs();
        System.assert(!result.isEmpty(), 'getSyncLogs should return records');
    }

    @IsTest
    static void testExtoleControllerTriggerSync() {
        // No active configs — just verify no exception
        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtoleController.triggerSync();
        Test.stopTest();

        System.assert(true, 'triggerSync should complete without exception');
    }

    @IsTest
    static void testExtractValueAggregations() {
        String json = '[{"referrals":"10","week":"2024-01-01"},{"referrals":"20","week":"2024-01-08"},{"referrals":"30","week":"2024-01-15"}]';

        System.assertEquals('10',  ExtoleSyncJob.extractValue(json, 'referrals', 'FIRST_ROW'),
            'FIRST_ROW should return first row value');
        System.assertEquals('60',  ExtoleSyncJob.extractValue(json, 'referrals', 'SUM'),
            'SUM should return total');
        System.assertEquals('3',   ExtoleSyncJob.extractValue(json, 'referrals', 'COUNT'),
            'COUNT should return row count');
    }

    @IsTest
    static void testDateRangeParam() {
        System.assertEquals('ROLLING_30_DAYS', ExtoleSyncJob.toDateRangeParam('Rolling 30'));
        System.assertEquals('ROLLING_90_DAYS', ExtoleSyncJob.toDateRangeParam('Rolling 90'));
        System.assertEquals('YEAR_TO_DATE',    ExtoleSyncJob.toDateRangeParam('YTD'));
    }

    @IsTest
    static void testMaxRetries() {
        System.assertEquals(10, ExtoleSyncJob.maxRetriesFor('SQL'));
        System.assertEquals(20, ExtoleSyncJob.maxRetriesFor('CONFIGURED'));
        System.assertEquals(40, ExtoleSyncJob.maxRetriesFor('SPARK'));
        System.assertEquals(20, ExtoleSyncJob.maxRetriesFor('UNKNOWN')); // default
    }

    @IsTest
    static void testScheduledExecution() {
        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        // Schedule a job and verify it runs without error
        String cronExp = '0 0 2 * * ?';
        System.schedule('Extole Sync Test', cronExp, new ExtoleSyncJob());
        Test.stopTest();

        System.assert(true, 'Scheduled job should be created without error');
    }
}
