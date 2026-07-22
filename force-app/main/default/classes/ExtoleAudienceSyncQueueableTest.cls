@IsTest(SeeAllData=true)
private class ExtoleAudienceSyncQueueableTest {
    private static Id testReportId() {
        return [
            SELECT Id
            FROM Report
            WHERE DeveloperName = 'Audience_Sync_Test_Leads'
            LIMIT 1
        ]
        .Id;
    }

    private static Extole_Audience_Cfg__c makeConfig(String key) {
        Extole_Audience_Cfg__c cfg = new Extole_Audience_Cfg__c(
            Config_Key__c = key,
            Extole_Audience_Name__c = key,
            Source_Report_Id__c = testReportId(),
            Identity_Column__c = 'EMAIL'
        );
        insert cfg;
        return cfg;
    }

    // NOTE: the happy-path branches of execute() (resolveAudienceId, submit operation)
    // can't be exercised from a unit test in this org — Reports.ReportManager.runReport()
    // does not see Lead records as report rows in Apex test context here, even when
    // loaded via Test.loadData() from a static resource (Salesforce's documented
    // workaround for exactly this gap). Confirmed empirically: a Lead loaded via
    // Test.loadData() still produces "Report returned 0 rows" from the real report
    // execution. Only the branches reachable without a populated report are covered
    // below; the rest of this file's uncovered lines are a real, external platform
    // limitation rather than a gap in this test suite's design.

    @IsTest
    static void testExecute_configNotFoundReturnsSilently() {
        Test.startTest();
        new ExtoleAudienceSyncQueueable('does_not_exist').execute(null);
        Test.stopTest();
        // No exception — nothing else to assert.
    }

    @IsTest
    static void testExecute_emptyReportMarksFailed() {
        // Defensive — the report filters on email containing "audiencetest"; make
        // sure no stray record from another run makes this report non-empty.
        delete [SELECT Id FROM Lead WHERE Email LIKE '%audiencetest%'];
        Extole_Audience_Cfg__c cfg = makeConfig('empty_report_cfg');

        Test.startTest();
        new ExtoleAudienceSyncQueueable('empty_report_cfg').execute(null);
        Test.stopTest();

        Extole_Audience_Cfg__c updated = [
            SELECT Last_Operation_State__c, Last_Error__c
            FROM Extole_Audience_Cfg__c
            WHERE Id = :cfg.Id
        ];
        System.assertEquals('FAILED', updated.Last_Operation_State__c);
        System.assert(updated.Last_Error__c.contains('0 rows'));

        List<Extole_Audience_Sync_Log__c> logs = [
            SELECT State__c
            FROM Extole_Audience_Sync_Log__c
            WHERE Config_Key__c = 'empty_report_cfg'
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('FAILED', logs[0].State__c);
    }
}
