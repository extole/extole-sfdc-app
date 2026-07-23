@IsTest
private class ExtoleLogPurgeJobTest {
    @IsTest
    static void testPurgesOldRecordsAcrossAllLogObjects() {
        DateTime oldTs = System.now().addDays(-31);
        DateTime recentTs = System.now().addDays(-1);

        insert new Extole_Sync_Log__c(Sync_Timestamp__c = oldTs);
        insert new Extole_Sync_Log__c(Sync_Timestamp__c = recentTs);

        insert new Extole_Debug_Log__c(Log_Timestamp__c = oldTs);
        insert new Extole_Debug_Log__c(Log_Timestamp__c = recentTs);

        insert new Extole_Event_Log__c(Timestamp__c = oldTs);
        insert new Extole_Event_Log__c(Timestamp__c = recentTs);

        insert new Extole_Backfill_Log__c(Started_At__c = oldTs);
        insert new Extole_Backfill_Log__c(Started_At__c = recentTs);

        insert new Extole_Writeback_Log__c(Received_At__c = oldTs);
        insert new Extole_Writeback_Log__c(Received_At__c = recentTs);

        insert new Extole_Event_Fire_Log__c(Timestamp__c = oldTs);
        insert new Extole_Event_Fire_Log__c(Timestamp__c = recentTs);

        insert new Extole_Audience_Sync_Log__c(Timestamp__c = oldTs);
        insert new Extole_Audience_Sync_Log__c(Timestamp__c = recentTs);

        Test.startTest();
        ExtoleLogPurgeJob.purgeOldLogs();
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Extole_Sync_Log__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Extole_Debug_Log__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Extole_Event_Log__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Extole_Backfill_Log__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Extole_Writeback_Log__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Extole_Event_Fire_Log__c]);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Extole_Audience_Sync_Log__c]
        );

        System.assertEquals(
            recentTs,
            [SELECT Received_At__c FROM Extole_Writeback_Log__c LIMIT 1]
            .Received_At__c
        );
    }

    @IsTest
    static void testEnsureScheduledIsIdempotent() {
        Test.startTest();
        ExtoleLogPurgeJob.ensureScheduled();
        ExtoleLogPurgeJob.ensureScheduled();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id
            FROM CronTrigger
            WHERE
                CronJobDetail.Name LIKE 'ExtoleLogPurge_%'
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
        ];
        System.assertEquals(1, jobs.size());
    }

    @IsTest
    static void testSchedulableExecuteRunsPurge() {
        insert new Extole_Writeback_Log__c(
            Received_At__c = System.now().addDays(-31)
        );

        Test.startTest();
        String jobId = System.schedule(
            'ExtoleLogPurge_manual_test',
            '0 0 3 * * ?',
            new ExtoleLogPurgeJob()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertEquals(0, [SELECT COUNT() FROM Extole_Writeback_Log__c]);
    }
}
