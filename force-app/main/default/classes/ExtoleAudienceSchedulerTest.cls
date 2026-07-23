@IsTest
private class ExtoleAudienceSchedulerTest {
    private static Extole_Audience_Cfg__c makeConfig(
        String key,
        String cadence,
        Boolean active,
        DateTime lastSync,
        String state
    ) {
        Extole_Audience_Cfg__c config = new Extole_Audience_Cfg__c(
            Config_Key__c = key,
            Extole_Audience_Name__c = key,
            Source_Report_Id__c = null,
            Identity_Column__c = 'EMAIL',
            Sync_Cadence__c = cadence,
            Active__c = active,
            Last_Sync_At__c = lastSync,
            Last_Operation_State__c = state
        );
        insert config;
        return config;
    }

    @IsTest
    static void testExecute_enqueuesDueHourlyConfig() {
        makeConfig(
            'due_hourly',
            'Hourly',
            true,
            DateTime.now().addMinutes(-60),
            'READY'
        );

        Test.startTest();
        new ExtoleAudienceScheduler().execute(null);
        Test.stopTest();

        Extole_Audience_Cfg__c updated = [
            SELECT Last_Operation_State__c
            FROM Extole_Audience_Cfg__c
            WHERE Config_Key__c = 'due_hourly'
        ];
        System.assertEquals('FAILED', updated.Last_Operation_State__c);
    }

    @IsTest
    static void testExecute_skipsNotYetDueConfig() {
        makeConfig(
            'not_due',
            'Hourly',
            true,
            DateTime.now().addMinutes(-10),
            'READY'
        );

        Test.startTest();
        new ExtoleAudienceScheduler().execute(null);
        Test.stopTest();

        Extole_Audience_Cfg__c updated = [
            SELECT Last_Operation_State__c
            FROM Extole_Audience_Cfg__c
            WHERE Config_Key__c = 'not_due'
        ];
        System.assertEquals('READY', updated.Last_Operation_State__c);
    }

    @IsTest
    static void testExecute_skipsInFlightConfig() {
        makeConfig(
            'in_flight',
            'Hourly',
            true,
            DateTime.now().addMinutes(-120),
            'BUILDING'
        );

        Test.startTest();
        new ExtoleAudienceScheduler().execute(null);
        Test.stopTest();

        Extole_Audience_Cfg__c updated = [
            SELECT Last_Operation_State__c
            FROM Extole_Audience_Cfg__c
            WHERE Config_Key__c = 'in_flight'
        ];
        System.assertEquals('BUILDING', updated.Last_Operation_State__c);
    }

    @IsTest
    static void testExecute_neverSyncedConfigIsDue() {
        makeConfig('never_synced', 'Daily', true, null, null);

        Test.startTest();
        new ExtoleAudienceScheduler().execute(null);
        Test.stopTest();

        Extole_Audience_Cfg__c updated = [
            SELECT Last_Operation_State__c
            FROM Extole_Audience_Cfg__c
            WHERE Config_Key__c = 'never_synced'
        ];
        System.assertEquals('FAILED', updated.Last_Operation_State__c);
    }

    @IsTest
    static void testExecute_dailyNotDueUntil23Hours() {
        makeConfig(
            'daily_not_due',
            'Daily',
            true,
            DateTime.now().addHours(-1),
            'READY'
        );

        Test.startTest();
        new ExtoleAudienceScheduler().execute(null);
        Test.stopTest();

        Extole_Audience_Cfg__c updated = [
            SELECT Last_Operation_State__c
            FROM Extole_Audience_Cfg__c
            WHERE Config_Key__c = 'daily_not_due'
        ];
        System.assertEquals('READY', updated.Last_Operation_State__c);
    }

    @IsTest
    static void testExecute_weeklyDueAfterAlmost7Days() {
        makeConfig(
            'weekly_due',
            'Weekly',
            true,
            DateTime.now().addDays(-7),
            'READY'
        );

        Test.startTest();
        new ExtoleAudienceScheduler().execute(null);
        Test.stopTest();

        Extole_Audience_Cfg__c updated = [
            SELECT Last_Operation_State__c
            FROM Extole_Audience_Cfg__c
            WHERE Config_Key__c = 'weekly_due'
        ];
        System.assertEquals('FAILED', updated.Last_Operation_State__c);
    }

    @IsTest
    static void testEnsureScheduled_isIdempotent() {
        Test.startTest();
        ExtoleAudienceScheduler.ensureScheduled();
        ExtoleAudienceScheduler.ensureScheduled();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id
            FROM CronTrigger
            WHERE
                CronJobDetail.Name = :ExtoleAudienceScheduler.JOB_NAME
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
        ];
        System.assertEquals(1, jobs.size());
    }
}
