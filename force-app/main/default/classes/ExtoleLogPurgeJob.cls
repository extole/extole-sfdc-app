public class ExtoleLogPurgeJob implements Schedulable {
    private static final String JOB_NAME_PREFIX = 'ExtoleLogPurge_';
    private static final Integer RETENTION_DAYS = 30;
    private static final Integer MAX_DELETE_PER_RUN = 1000;

    public void execute(SchedulableContext context) {
        purgeOldLogs();
    }

    public static void purgeOldLogs() {
        DateTime cutoff = System.now().addDays(-RETENTION_DAYS);

        purgeLogType('Extole_Sync_Log__c', 'Sync_Timestamp__c', cutoff);
        purgeLogType('Extole_Debug_Log__c', 'Log_Timestamp__c', cutoff);
        purgeLogType('Extole_Event_Log__c', 'Timestamp__c', cutoff);
        purgeLogType('Extole_Backfill_Log__c', 'Started_At__c', cutoff);
        purgeLogType('Extole_Writeback_Log__c', 'Received_At__c', cutoff);
        purgeLogType('Extole_Event_Fire_Log__c', 'Timestamp__c', cutoff);
        purgeLogType('Extole_Audience_Sync_Log__c', 'Timestamp__c', cutoff);
    }

    private static void purgeLogType(
        String objectApiName,
        String dateFieldApiName,
        DateTime cutoff
    ) {
        String query =
            'SELECT Id FROM ' +
            objectApiName +
            ' WHERE ' +
            dateFieldApiName +
            ' < :cutoff LIMIT ' +
            MAX_DELETE_PER_RUN;
        List<SObject> toDelete = Database.query(query);
        if (!toDelete.isEmpty())
            delete toDelete;
    }

    public static void ensureScheduled() {
        List<CronTrigger> existing = [
            SELECT Id
            FROM CronTrigger
            WHERE
                CronJobDetail.Name LIKE :(JOB_NAME_PREFIX + '%')
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
            LIMIT 1
        ];
        if (!existing.isEmpty())
            return;

        System.schedule(
            JOB_NAME_PREFIX + String.valueOf(System.currentTimeMillis()),
            '0 0 3 * * ?',
            new ExtoleLogPurgeJob()
        );
    }
}
