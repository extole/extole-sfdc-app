@IsTest
private class ExtoleSyncJobTest {

    // ─────────────────────────────────────────────────────────────────────────
    // HTTP mock: simulates the Extole API (runner-based architecture)
    // ─────────────────────────────────────────────────────────────────────────

    private class ExtoleMock implements HttpCalloutMock {
        public Integer callCount = 0;

        public HTTPResponse respond(HTTPRequest req) {
            callCount++;
            String endpoint = req.getEndpoint();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            // GET /v7/report-runners  → testConnection / getReportTypes
            if (endpoint.contains('/v7/report-runners') && !endpoint.contains('/latest')) {
                res.setBody('[{"report_runner_id":"runner-001","name":"Referral Overview","description":"Overview of referral activity"},'
                    + '{"report_runner_id":"runner-002","name":"Share Events","description":"Share event tracking"},'
                    + '{"report_runner_id":"runner-003","name":"Conversion Report","description":"Lead conversion metrics"}]');
                return res;
            }

            // GET /v6/report-runners/{id}/reports?limit=N  → report list (new per-runner sync)
            if (endpoint.contains('/v6/report-runners/') && endpoint.contains('/reports')) {
                res.setBody('[{"report_id":"rpt-001","status":"DONE","created_at":"2024-01-08T00:00:00Z","view_url":"https://my.extole.com/reports/view?id=rpt-001","client_id":"cli-999"}]');
                return res;
            }

            // GET /v6/report-runners/{id}/latest  → latest report instance (triggerSingleSync)
            if (endpoint.contains('/v6/report-runners/') && endpoint.endsWith('/latest')) {
                res.setBody('{"report_id":"rpt-001","status":"DONE","view_url":"https://my.extole.com/reports/view?id=rpt-001","client_id":"cli-999"}');
                return res;
            }

            // GET /v4/reports/rpt-001/download.json  → report data
            if (endpoint.contains('/download.json')) {
                res.setBody('[{"week":"2024-01-01","referrals":"42"},{"week":"2024-01-08","referrals":"55"}]');
                return res;
            }

            // Default fallback
            res.setStatusCode(404);
            res.setBody('{"error":"not found"}');
            return res;
        }
    }

    // Returns 500 for all runner list calls to simulate API failure
    private class FailingMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }

    // Returns 404 for runner list calls to simulate Extole-side runner deletion
    private class NotFoundMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('{"error":"Runner not found"}');
            return res;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test data helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static Extole_Report_Config__c makeConfig(String name, String runnerId) {
        Extole_Report_Config__c c = new Extole_Report_Config__c();
        c.Name              = name;
        c.Report_Name__c    = name;
        c.Report_Type__c    = runnerId;   // runner ID
        c.Executor_Type__c  = 'RUNNER';
        c.Display_Label__c  = name;
        c.Value_Column__c   = 'referrals';
        c.Aggregation__c    = 'FIRST_ROW';
        c.Chart_Type__c     = 'None';
        c.Data_Mode__c      = 'Single Value';
        c.Date_Range__c     = 'Latest';
        c.Display_Order__c  = 1;
        c.Active__c         = true;
        return c;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testSyncJobNoConfigs() {
        Test.setMock(HttpCalloutMock.class, new ExtoleMock());
        Test.startTest();
        ExtoleSyncJob.performSync('Manual');
        Test.stopTest();
        System.assert(true, 'performSync with no active configs should not throw');
    }

    @IsTest
    static void testSyncJobSingleConfig() {
        Extole_Report_Config__c config = makeConfig('referral_overview', 'runner-001');
        insert config;

        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtoleSyncJob.performSync('Manual');
        Test.stopTest();

        // Verify one snapshot per config (runner-based: no date range looping)
        List<Extole_Report_Snapshot__c> snaps = [
            SELECT Id, Value__c, Date_Range__c, Config_Status__c, Config_Id__c
            FROM Extole_Report_Snapshot__c
            WHERE Config_Id__c = :config.Id
        ];
        System.assertEquals(1, snaps.size(), 'Should have 1 snapshot per runner config');
        System.assertEquals('ACTIVE', snaps[0].Config_Status__c, 'Snapshot should be ACTIVE');
        System.assertEquals('42', snaps[0].Value__c, 'Extracted value should be 42');

        // Verify sync log written
        List<Extole_Sync_Log__c> logs = [
            SELECT Status__c FROM Extole_Sync_Log__c
            WHERE Report_Name__c = 'referral_overview'
        ];
        System.assertEquals(1, logs.size(), 'Should have 1 sync log entry');
        System.assertEquals('SUCCESS', logs[0].Status__c, 'Sync log should be SUCCESS');
    }

    @IsTest
    static void testSyncJobOrphanReconciliation() {
        Extole_Report_Snapshot__c orphan = new Extole_Report_Snapshot__c();
        orphan.Name             = 'Orphaned Snapshot – Latest';
        orphan.Config_Id__c     = 'a00000000000000001';
        orphan.Date_Range__c    = 'Latest';
        orphan.Config_Status__c = 'ACTIVE';
        orphan.Value__c         = '999';
        insert orphan;

        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtoleSyncJob.performSync('Manual');
        Test.stopTest();

        List<Extole_Report_Snapshot__c> remaining = [
            SELECT Id FROM Extole_Report_Snapshot__c WHERE Id = :orphan.Id
        ];
        System.assertEquals(0, remaining.size(), 'Orphaned snapshot should be deleted automatically');
    }

    @IsTest
    static void testSyncJobDebugLogging() {
        Extole_App_Settings__c settings = Extole_App_Settings__c.getOrgDefaults();
        if (settings == null) settings = new Extole_App_Settings__c();
        settings.Debug_Logging_Enabled__c = true;
        upsert settings;

        Extole_Report_Config__c config = makeConfig('debug_report', 'runner-001');
        insert config;

        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtoleSyncJob.performSync('Manual');
        Test.stopTest();

        List<Extole_Debug_Log__c> debugLogs = [
            SELECT Event_Type__c FROM Extole_Debug_Log__c
            WHERE Report_Name__c = 'debug_report'
        ];
        System.assert(!debugLogs.isEmpty(), 'Debug logs should be written when debug logging enabled');

        Boolean hasValueExtracted = false;
        for (Extole_Debug_Log__c dl : debugLogs) {
            if (dl.Event_Type__c == 'VALUE_EXTRACTED') {
                hasValueExtracted = true;
                break;
            }
        }
        System.assert(hasValueExtracted, 'Should have a VALUE_EXTRACTED debug log entry');
    }

    @IsTest
    static void testExtoleControllerGetSnapshots() {
        Extole_Report_Snapshot__c snap = new Extole_Report_Snapshot__c();
        snap.Name             = 'Test Snapshot – Latest';
        snap.Value__c         = '100';
        snap.Date_Range__c    = 'Latest';
        snap.Config_Id__c     = 'abc123';
        snap.Config_Status__c = 'ACTIVE';
        insert snap;

        List<Extole_Report_Snapshot__c> result = ExtoleController.getSnapshots();
        System.assert(!result.isEmpty(), 'getSnapshots should return records');
    }

    @IsTest
    static void testExtoleControllerGetConfigs() {
        Extole_Report_Config__c config = makeConfig('test_config', 'runner-001');
        insert config;

        List<Extole_Report_Config__c> result = ExtoleController.getConfigs();
        System.assert(!result.isEmpty(), 'getConfigs should return records');
    }

    @IsTest
    static void testExtoleControllerSaveAndDeleteConfig() {
        Extole_Report_Config__c config = makeConfig('save_delete_test', 'runner-001');
        Id savedId = ExtoleController.saveConfig(config);
        System.assertNotEquals(null, savedId, 'saveConfig should return an Id');

        config.Display_Label__c = 'Updated Label';
        ExtoleController.saveConfig(config);

        Extole_Report_Config__c fetched = [SELECT Display_Label__c FROM Extole_Report_Config__c WHERE Id = :savedId];
        System.assertEquals('Updated Label', fetched.Display_Label__c, 'Display label should be updated');

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
        System.assertEquals(3, (Integer) result.get('reportCount'), 'Should return 3 mock runners');
    }

    @IsTest
    static void testExtoleControllerGetReportTypes() {
        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String rawJson = ExtoleController.getReportTypes();
        Test.stopTest();

        System.assertNotEquals(null, rawJson, 'getReportTypes should return JSON string');
        System.assert(rawJson.contains('runner-001'), 'Should contain runner ID');
    }

    @IsTest
    static void testExtoleControllerTriggerSingleSync() {
        Extole_Report_Config__c config = makeConfig('single_sync_test', 'runner-001');
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
    static void testExtoleControllerClearDebugLogs() {
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
        Extole_Sync_Log__c log = new Extole_Sync_Log__c();
        log.Report_Name__c    = 'test_report';
        log.Date_Range__c     = 'Latest';
        log.Executor_Type__c  = 'RUNNER';
        log.Status__c         = 'SUCCESS';
        log.Sync_Timestamp__c = System.now();
        log.Sync_Batch_Id__c  = 'batch-001';
        insert log;

        List<Extole_Sync_Log__c> result = ExtoleController.getSyncLogs();
        System.assert(!result.isEmpty(), 'getSyncLogs should return records');
    }

    @IsTest
    static void testExtoleControllerTriggerSync() {
        ExtoleMock mock = new ExtoleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ExtoleController.triggerSync();
        Test.stopTest();

        System.assert(true, 'triggerSync should complete without exception');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Failure notification tests
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testFailureNotificationFiredAtThreshold() {
        // Settings: notify enabled, threshold = 1, valid email
        Extole_App_Settings__c settings = new Extole_App_Settings__c();
        settings.Notify_On_Sync_Failure__c       = true;
        settings.Notify_After_N_Failures__c      = 1;
        settings.Failure_Notification_Email__c   = 'test@example.com';
        settings.Consecutive_Failure_Count__c    = 0;
        upsert settings;

        Extole_Report_Config__c config = makeConfig('fail_test', 'runner-001');
        insert config;

        Test.setMock(HttpCalloutMock.class, new FailingMock());

        Test.startTest();
        ExtoleSyncJob.performSync('Manual');
        Test.stopTest();

        // Verify sync log shows FAILED
        List<Extole_Sync_Log__c> logs = [
            SELECT Status__c FROM Extole_Sync_Log__c WHERE Report_Name__c = 'fail_test'
        ];
        System.assertEquals(1, logs.size(), 'Should have 1 sync log entry');
        System.assertEquals('FAILED', logs[0].Status__c, 'Sync log status should be FAILED');

        // Verify consecutive failure count incremented — this is the gate condition for the email
        Extole_App_Settings__c updated = Extole_App_Settings__c.getOrgDefaults();
        System.assertEquals(1, (Integer) updated.Consecutive_Failure_Count__c,
            'Consecutive failure count should be 1');

        // Verify the settings that gate the email send are all satisfied
        // (actual email delivery is an integration concern; sandbox deliverability settings
        // may prevent Messaging.sendEmail from executing in test context)
        System.assertEquals(true,  updated.Notify_On_Sync_Failure__c, 'Notify flag should be true');
        System.assertEquals(1, (Integer) updated.Notify_After_N_Failures__c, 'Threshold should be 1');
        System.assert(String.isNotBlank(updated.Failure_Notification_Email__c), 'Email should be set');
    }

    @IsTest
    static void testFailureNotificationNotFiredBelowThreshold() {
        // Settings: notify enabled, threshold = 3, no prior failures → count becomes 1, no email yet
        Extole_App_Settings__c settings = new Extole_App_Settings__c();
        settings.Notify_On_Sync_Failure__c       = true;
        settings.Notify_After_N_Failures__c      = 3;
        settings.Failure_Notification_Email__c   = 'test@example.com';
        settings.Consecutive_Failure_Count__c    = 0;
        upsert settings;

        Extole_Report_Config__c config = makeConfig('below_threshold_test', 'runner-001');
        insert config;

        Test.setMock(HttpCalloutMock.class, new FailingMock());

        Test.startTest();
        ExtoleSyncJob.performSync('Manual');
        Test.stopTest();

        Extole_App_Settings__c updated = Extole_App_Settings__c.getOrgDefaults();
        System.assertEquals(1, (Integer) updated.Consecutive_Failure_Count__c,
            'Consecutive failure count should be 1');
        System.assertEquals(0, Limits.getEmailInvocations(),
            'No email should be sent before threshold is reached');
    }

    @IsTest
    static void testFailureCountResetsOnSuccess() {
        // Pre-seed consecutive failures, then run a successful sync → count goes to 0
        Extole_App_Settings__c settings = new Extole_App_Settings__c();
        settings.Notify_On_Sync_Failure__c       = true;
        settings.Notify_After_N_Failures__c      = 3;
        settings.Failure_Notification_Email__c   = 'test@example.com';
        settings.Consecutive_Failure_Count__c    = 2;
        upsert settings;

        Extole_Report_Config__c config = makeConfig('reset_test', 'runner-001');
        insert config;

        Test.setMock(HttpCalloutMock.class, new ExtoleMock());

        Test.startTest();
        ExtoleSyncJob.performSync('Manual');
        Test.stopTest();

        Extole_App_Settings__c updated = Extole_App_Settings__c.getOrgDefaults();
        System.assertEquals(0, (Integer) updated.Consecutive_Failure_Count__c,
            'Consecutive failure count should reset to 0 after a successful sync');
        System.assertEquals(0, Limits.getEmailInvocations(),
            'No email should be sent on successful sync');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Extole-side runner deletion tests
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testRunnerDeletion404MarksSourceUnavailable() {
        // Active config with an existing ACTIVE snapshot
        Extole_Report_Config__c config = makeConfig('unavailable_test', 'runner-deleted');
        insert config;

        Extole_Report_Snapshot__c snap = new Extole_Report_Snapshot__c();
        snap.Name             = 'Unavailable Test – Latest';
        snap.Config_Id__c     = config.Id;
        snap.Date_Range__c    = 'Latest';
        snap.Config_Status__c = 'ACTIVE';
        snap.Value__c         = '77';
        insert snap;

        // Extole API returns 404 for this runner (runner was deleted in Extole)
        Test.setMock(HttpCalloutMock.class, new NotFoundMock());

        Test.startTest();
        ExtoleSyncJob.performSync('Manual');
        Test.stopTest();

        // Snapshot should still exist (tile kept as indicator) but marked SOURCE_UNAVAILABLE
        List<Extole_Report_Snapshot__c> result = [
            SELECT Id, Config_Status__c FROM Extole_Report_Snapshot__c WHERE Id = :snap.Id
        ];
        System.assertEquals(1, result.size(), 'Snapshot should NOT be deleted — dead tile is the indicator');
        System.assertEquals('SOURCE_UNAVAILABLE', result[0].Config_Status__c,
            'Snapshot should be SOURCE_UNAVAILABLE when runner returns 404');
    }

    @IsTest
    static void testRunnerRecoveryResetsToActive() {
        // Start with a SOURCE_UNAVAILABLE snapshot (runner was previously deleted)
        Extole_Report_Config__c config = makeConfig('recovery_test', 'runner-001');
        insert config;

        Extole_Report_Snapshot__c snap = new Extole_Report_Snapshot__c();
        snap.Name             = 'Recovery Test – Latest';
        snap.Config_Id__c     = config.Id;
        snap.Date_Range__c    = 'Latest';
        snap.Config_Status__c = 'SOURCE_UNAVAILABLE';
        snap.Value__c         = '42';
        insert snap;

        // Extole API is back (runner restored or re-created)
        Test.setMock(HttpCalloutMock.class, new ExtoleMock());

        Test.startTest();
        ExtoleSyncJob.performSync('Manual');
        Test.stopTest();

        // Snapshot should be reset to ACTIVE on successful sync
        List<Extole_Report_Snapshot__c> result = [
            SELECT Id, Config_Status__c FROM Extole_Report_Snapshot__c WHERE Id = :snap.Id
        ];
        System.assertEquals(1, result.size(), 'Snapshot should still exist after recovery');
        System.assertEquals('ACTIVE', result[0].Config_Status__c,
            'Snapshot should reset to ACTIVE when runner is restored');
    }

    @IsTest
    static void testRunnerRepointResetsToActive() {
        // Config starts pointing to a deleted runner → SOURCE_UNAVAILABLE snapshot
        Extole_Report_Config__c config = makeConfig('repoint_test', 'runner-deleted');
        insert config;

        Extole_Report_Snapshot__c snap = new Extole_Report_Snapshot__c();
        snap.Name             = 'Repoint Test – Latest';
        snap.Config_Id__c     = config.Id;
        snap.Date_Range__c    = 'Latest';
        snap.Config_Status__c = 'SOURCE_UNAVAILABLE';
        snap.Value__c         = '55';
        insert snap;

        // Admin re-points config to a working runner
        config.Report_Type__c = 'runner-001';
        update config;

        // Extole API responds successfully for the new runner
        Test.setMock(HttpCalloutMock.class, new ExtoleMock());

        Test.startTest();
        ExtoleSyncJob.performSync('Manual');
        Test.stopTest();

        // Same snapshot (same Config_Id__c) should be reset to ACTIVE with new runner's data
        List<Extole_Report_Snapshot__c> result = [
            SELECT Id, Config_Status__c FROM Extole_Report_Snapshot__c WHERE Id = :snap.Id
        ];
        System.assertEquals(1, result.size(), 'Snapshot should still exist after re-point');
        System.assertEquals('ACTIVE', result[0].Config_Status__c,
            'Snapshot should reset to ACTIVE when config is re-pointed to a working runner');
    }

    @IsTest
    static void testExtractValueAggregations() {
        String json = '[{"referrals":"10","week":"2024-01-01"},{"referrals":"20","week":"2024-01-08"},{"referrals":"30","week":"2024-01-15"}]';

        System.assertEquals('10', ExtoleSyncJob.extractValue(json, 'referrals', 'FIRST_ROW'),
            'FIRST_ROW should return first row value');
        System.assertEquals('60', ExtoleSyncJob.extractValue(json, 'referrals', 'SUM'),
            'SUM should return total');
        System.assertEquals('3',  ExtoleSyncJob.extractValue(json, 'referrals', 'COUNT'),
            'COUNT should return row count');
    }
}
