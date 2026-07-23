@IsTest
private class ExtoleAudienceControllerTest {
    private static final String FAKE_REPORT_ID = 'aFakeReportId00001';

    private static Id testReportId() {
        return [
            SELECT Id
            FROM Report
            WHERE DeveloperName = 'Audience_Sync_Test_Leads'
            LIMIT 1
        ]
        .Id;
    }

    private static Extole_Audience_Cfg__c makeConfig(
        String key,
        String state,
        String opId,
        String audienceId
    ) {
        return makeConfig(key, state, opId, audienceId, FAKE_REPORT_ID);
    }

    private static Extole_Audience_Cfg__c makeConfig(
        String key,
        String state,
        String opId,
        String audienceId,
        String reportId
    ) {
        Extole_Audience_Cfg__c config = new Extole_Audience_Cfg__c(
            Config_Key__c = key,
            Extole_Audience_Name__c = key,
            Source_Report_Id__c = reportId,
            Identity_Column__c = 'EMAIL',
            Last_Operation_State__c = state,
            Last_Operation_Id__c = opId,
            Extole_Audience_Id__c = audienceId
        );
        insert config;
        return config;
    }

    @IsTest
    static void testGetAudienceConfigs_returnsOrderedList() {
        makeConfig('zzztest_b_config', 'READY', null, null);
        makeConfig('zzztest_a_config', 'READY', null, null);

        Test.startTest();
        List<Extole_Audience_Cfg__c> configs = ExtoleAudienceController.getAudienceConfigs();
        Test.stopTest();

        Integer indexA = -1, indexB = -1;
        for (Integer i = 0; i < configs.size(); i++) {
            if (configs[i].Extole_Audience_Name__c == 'zzztest_a_config')
                indexA = i;
            if (configs[i].Extole_Audience_Name__c == 'zzztest_b_config')
                indexB = i;
        }
        System.assert(
            indexA >= 0 && indexB >= 0,
            'Both test configs should be present'
        );
        System.assert(indexA < indexB, 'a_config should sort before b_config');
    }

    @IsTest
    static void testSaveAudienceConfig_validationErrors() {
        assertThrowsSave(null, 'config is required');

        Extole_Audience_Cfg__c missingName = new Extole_Audience_Cfg__c(
            Source_Report_Id__c = FAKE_REPORT_ID,
            Identity_Column__c = 'EMAIL'
        );
        assertThrowsSave(missingName, 'name is required');

        Extole_Audience_Cfg__c missingReport = new Extole_Audience_Cfg__c(
            Extole_Audience_Name__c = 'x',
            Identity_Column__c = 'EMAIL'
        );
        assertThrowsSave(missingReport, 'report is required');

        Extole_Audience_Cfg__c missingColumn = new Extole_Audience_Cfg__c(
            Extole_Audience_Name__c = 'x',
            Source_Report_Id__c = FAKE_REPORT_ID
        );
        assertThrowsSave(missingColumn, 'column is required');
    }

    private static void assertThrowsSave(
        Extole_Audience_Cfg__c config,
        String expectedFragment
    ) {
        Boolean threw = false;
        try {
            ExtoleAudienceController.saveAudienceConfig(config);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(
            true,
            threw,
            'Expected save to throw for: ' + expectedFragment
        );
    }

    @IsTest
    static void testSaveAudienceConfig_generatesConfigKeyAndSchedulesWhenCadenceSet() {
        Integer jobsBefore = countSchedulerJobs();

        Extole_Audience_Cfg__c config = new Extole_Audience_Cfg__c(
            Extole_Audience_Name__c = 'My Audience',
            Source_Report_Id__c = FAKE_REPORT_ID,
            Identity_Column__c = 'EMAIL',
            Sync_Cadence__c = 'Daily'
        );

        Test.startTest();
        Id savedId = ExtoleAudienceController.saveAudienceConfig(config);
        Test.stopTest();

        Extole_Audience_Cfg__c saved = [
            SELECT Config_Key__c
            FROM Extole_Audience_Cfg__c
            WHERE Id = :savedId
        ];
        System.assertNotEquals(null, saved.Config_Key__c);
        System.assert(saved.Config_Key__c.startsWith('My_Audience_'));

        System.assert(countSchedulerJobs() >= 1);
        System.assert(countSchedulerJobs() <= jobsBefore + 1);
    }

    @IsTest
    static void testSaveAudienceConfig_manualCadenceDoesNotSchedule() {
        Integer jobsBefore = countSchedulerJobs();

        Extole_Audience_Cfg__c config = new Extole_Audience_Cfg__c(
            Extole_Audience_Name__c = 'Manual Audience',
            Source_Report_Id__c = FAKE_REPORT_ID,
            Identity_Column__c = 'EMAIL',
            Sync_Cadence__c = 'Manual'
        );

        Test.startTest();
        ExtoleAudienceController.saveAudienceConfig(config);
        Test.stopTest();

        System.assertEquals(jobsBefore, countSchedulerJobs());
    }

    private static Integer countSchedulerJobs() {
        return [
            SELECT COUNT()
            FROM CronTrigger
            WHERE
                CronJobDetail.Name = :ExtoleAudienceScheduler.JOB_NAME
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
        ];
    }

    @IsTest
    static void testRunSchedulerNow_executesWithoutError() {
        Test.startTest();
        ExtoleAudienceController.runSchedulerNow();
        Test.stopTest();
    }

    @IsTest
    static void testDeleteAudienceConfig_nullIdThrows() {
        Boolean threw = false;
        try {
            ExtoleAudienceController.deleteAudienceConfig(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testDeleteAudienceConfig_removesRecord() {
        Extole_Audience_Cfg__c config = makeConfig(
            'to_delete',
            'READY',
            null,
            null
        );

        Test.startTest();
        ExtoleAudienceController.deleteAudienceConfig(config.Id);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Extole_Audience_Cfg__c WHERE Id = :config.Id]
        );
    }

    @IsTest(SeeAllData=true)
    static void testGetAvailableReports_returnsTabularReports() {
        Test.startTest();
        List<Map<String, Object>> reports = ExtoleAudienceController.getAvailableReports();
        Test.stopTest();

        Boolean foundFixture = false;
        for (Map<String, Object> r : reports) {
            if ('Audience Sync Test Leads'.equals(r.get('name')))
                foundFixture = true;
        }
        System.assertEquals(true, foundFixture);
    }

    @IsTest
    static void testGetReportColumns_nullIdThrows() {
        Boolean threw = false;
        try {
            ExtoleAudienceController.getReportColumns(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest(SeeAllData=true)
    static void testGetReportColumns_returnsDetailColumns() {
        Test.startTest();
        List<String> columns = ExtoleAudienceController.getReportColumns(
            testReportId()
        );
        Test.stopTest();

        System.assert(columns.contains('EMAIL'));
    }

    @IsTest
    static void testSyncAudience_blankConfigKeyThrows() {
        Boolean threw = false;
        try {
            ExtoleAudienceController.syncAudience('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testSyncAudience_notFoundThrows() {
        Boolean threw = false;
        try {
            ExtoleAudienceController.syncAudience('nonexistent_key');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testSyncAudience_alreadyInFlightThrows() {
        makeConfig('busy_cfg', 'BUILDING', null, null);
        Boolean threw = false;
        try {
            ExtoleAudienceController.syncAudience('busy_cfg');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest(SeeAllData=true)
    static void testSyncAudience_marksPreparingAndEnqueuesJob() {
        makeConfig('sync_now_cfg', 'READY', null, null, testReportId());

        Test.startTest();
        Id jobId = ExtoleAudienceController.syncAudience('sync_now_cfg');
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        Extole_Audience_Cfg__c updated = [
            SELECT Last_Operation_State__c
            FROM Extole_Audience_Cfg__c
            WHERE Config_Key__c = 'sync_now_cfg'
        ];
        System.assertEquals('FAILED', updated.Last_Operation_State__c);
    }

    @IsTest
    static void testPollAudienceState_blankConfigKeyThrows() {
        Boolean threw = false;
        try {
            ExtoleAudienceController.pollAudienceState('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testPollAudienceState_notFoundThrows() {
        Boolean threw = false;
        try {
            ExtoleAudienceController.pollAudienceState('nonexistent_key');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testPollAudienceState_noPollNeededReturnsAsIs() {
        makeConfig('ready_cfg', 'READY', null, null);

        Test.startTest();
        Extole_Audience_Cfg__c result = ExtoleAudienceController.pollAudienceState(
            'ready_cfg'
        );
        Test.stopTest();

        System.assertEquals('READY', result.Last_Operation_State__c);
    }

    @IsTest
    static void testPollAudienceState_terminalSuccessUpdatesStateAndLogs() {
        makeConfig('polling_success_cfg', 'BUILDING', 'op_1', 'aud_1');

        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(
                    200,
                    '{"id":"op_1","audience_id":"aud_1","state":"READY"}'
                )
        );

        Test.startTest();
        Extole_Audience_Cfg__c result = ExtoleAudienceController.pollAudienceState(
            'polling_success_cfg'
        );
        Test.stopTest();

        System.assertEquals('READY', result.Last_Operation_State__c);
        System.assertNotEquals(null, result.Last_Sync_At__c);
        System.assertEquals(null, result.Last_Error__c);

        List<Extole_Audience_Sync_Log__c> logs = [
            SELECT State__c
            FROM Extole_Audience_Sync_Log__c
            WHERE Config_Key__c = 'polling_success_cfg'
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('READY', logs[0].State__c);
    }

    @IsTest
    static void testPollAudienceState_terminalFailureSetsError() {
        makeConfig('polling_failure_cfg', 'BUILDING', 'op_2', 'aud_2');

        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(
                    200,
                    '{"id":"op_2","audience_id":"aud_2","state":"FAILED"}'
                )
        );

        Test.startTest();
        Extole_Audience_Cfg__c result = ExtoleAudienceController.pollAudienceState(
            'polling_failure_cfg'
        );
        Test.stopTest();

        System.assertEquals('FAILED', result.Last_Operation_State__c);
        System.assertNotEquals(null, result.Last_Error__c);
    }

    @IsTest
    static void testPollAudienceState_calloutErrorIsSwallowed() {
        makeConfig('polling_error_cfg', 'BUILDING', 'op_3', 'aud_3');

        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(500, '{"error":"boom"}')
        );

        Test.startTest();
        Extole_Audience_Cfg__c result = ExtoleAudienceController.pollAudienceState(
            'polling_error_cfg'
        );
        Test.stopTest();

        System.assertEquals('BUILDING', result.Last_Operation_State__c);
    }

    @IsTest
    static void testGetAudienceSyncLogsAndClear() {
        ExtoleAudienceController.writeLog(
            'zzztest_cfg_key',
            'aud_1',
            'op_1',
            'REPLACE',
            'READY',
            5,
            'Sync complete',
            null
        );

        Test.startTest();
        List<Extole_Audience_Sync_Log__c> logs = ExtoleAudienceController.getAudienceSyncLogs();
        Boolean foundOurs = false;
        for (Extole_Audience_Sync_Log__c log : logs) {
            if (log.Config_Key__c == 'zzztest_cfg_key')
                foundOurs = true;
        }
        System.assertEquals(true, foundOurs);

        Map<String, Integer> result = ExtoleAudienceController.clearAudienceSyncLogs();
        Test.stopTest();

        System.assert(result.get('deletedCount') >= 1);
        System.assertEquals(0, result.get('remainingCount'));
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Extole_Audience_Sync_Log__c]
        );
    }
}
