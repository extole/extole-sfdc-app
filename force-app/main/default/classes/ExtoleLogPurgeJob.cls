/**
 * ExtoleLogPurgeJob
 *
 * Deletes log records older than 30 days across every log object the app
 * writes to. Runs on its own daily schedule, independent of the KPI Dashboard
 * sync job — so retention applies whether or not KPI syncing is configured.
 *
 * ensureScheduled() is idempotent and safe to call from any tab's load path;
 * it only registers the job if one isn't already active.
 */
public class ExtoleLogPurgeJob implements Schedulable {
    private static final String JOB_NAME_PREFIX = 'ExtoleLogPurge_';
    private static final Integer RETENTION_DAYS = 30;

    public void execute(SchedulableContext ctx) {
        purgeOldLogs();
    }

    public static void purgeOldLogs() {
        DateTime cutoff = System.now().addDays(-RETENTION_DAYS);

        List<Extole_Sync_Log__c> oldSyncLogs = [
            SELECT Id
            FROM Extole_Sync_Log__c
            WHERE Sync_Timestamp__c < :cutoff
        ];
        if (!oldSyncLogs.isEmpty())
            delete oldSyncLogs;

        List<Extole_Debug_Log__c> oldDebugLogs = [
            SELECT Id
            FROM Extole_Debug_Log__c
            WHERE Log_Timestamp__c < :cutoff
        ];
        if (!oldDebugLogs.isEmpty())
            delete oldDebugLogs;

        List<Extole_Event_Log__c> oldEventLogs = [
            SELECT Id
            FROM Extole_Event_Log__c
            WHERE Timestamp__c < :cutoff
        ];
        if (!oldEventLogs.isEmpty())
            delete oldEventLogs;

        List<Extole_Backfill_Log__c> oldBackfillLogs = [
            SELECT Id
            FROM Extole_Backfill_Log__c
            WHERE Started_At__c < :cutoff
        ];
        if (!oldBackfillLogs.isEmpty())
            delete oldBackfillLogs;

        List<Extole_Writeback_Log__c> oldWritebackLogs = [
            SELECT Id
            FROM Extole_Writeback_Log__c
            WHERE Received_At__c < :cutoff
        ];
        if (!oldWritebackLogs.isEmpty())
            delete oldWritebackLogs;

        List<Extole_Event_Fire_Log__c> oldFireLogs = [
            SELECT Id
            FROM Extole_Event_Fire_Log__c
            WHERE Timestamp__c < :cutoff
        ];
        if (!oldFireLogs.isEmpty())
            delete oldFireLogs;

        List<Extole_Audience_Sync_Log__c> oldAudienceSyncLogs = [
            SELECT Id
            FROM Extole_Audience_Sync_Log__c
            WHERE Timestamp__c < :cutoff
        ];
        if (!oldAudienceSyncLogs.isEmpty())
            delete oldAudienceSyncLogs;
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
            '0 0 3 * * ?', // nightly at 3 AM
            new ExtoleLogPurgeJob()
        );
    }
}
