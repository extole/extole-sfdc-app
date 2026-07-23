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
        Extole_Audience_Cfg__c config = new Extole_Audience_Cfg__c(
            Config_Key__c = key,
            Extole_Audience_Name__c = key,
            Source_Report_Id__c = testReportId(),
            Identity_Column__c = 'EMAIL'
        );
        insert config;
        return config;
    }

    @IsTest
    static void testExecute_configNotFoundReturnsSilently() {
        Test.startTest();
        new ExtoleAudienceSyncQueueable('does_not_exist').execute(null);
        Test.stopTest();
    }

    @IsTest
    static void testExecute_emptyReportMarksFailed() {
        delete [SELECT Id FROM Lead WHERE Email LIKE '%audiencetest%'];
        Extole_Audience_Cfg__c config = makeConfig('empty_report_cfg');

        Test.startTest();
        new ExtoleAudienceSyncQueueable('empty_report_cfg').execute(null);
        Test.stopTest();

        Extole_Audience_Cfg__c updated = [
            SELECT Last_Operation_State__c, Last_Error__c
            FROM Extole_Audience_Cfg__c
            WHERE Id = :config.Id
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
