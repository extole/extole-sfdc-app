/**
 * ExtoleAudienceScheduler
 *
 * Fires hourly. For every active audience config whose cadence != 'Manual',
 * enqueues an ExtoleAudienceSyncQueueable if the config is due based on
 * Last_Sync_At__c.
 *
 *   Hourly  → due ≥ 50 minutes after the last sync
 *   Daily   → due ≥ 23 hours
 *   Weekly  → due ≥ 6 days, 20 hours
 *
 * Configs whose previous operation is still in flight (PREPARING/BUILDING/
 * VALIDATING) are skipped — Extole rejects concurrent operations per audience.
 */
public with sharing class ExtoleAudienceScheduler implements Schedulable {

    public static final String JOB_NAME    = 'Extole Audience Scheduler';
    public static final String CRON_HOURLY = '0 0 * * * ?';

    public void execute(SchedulableContext ctx) {
        DateTime now = DateTime.now();
        List<Extole_Audience_Cfg__c> all = [
            SELECT Id, Config_Key__c, Sync_Cadence__c, Active__c,
                   Last_Sync_At__c, Last_Operation_State__c
            FROM Extole_Audience_Cfg__c
            WHERE Active__c = true AND Sync_Cadence__c != null AND Sync_Cadence__c != 'Manual'
        ];
        for (Extole_Audience_Cfg__c cfg : all) {
            if (isInFlight(cfg.Last_Operation_State__c)) continue;
            if (!isDue(cfg, now)) continue;
            System.enqueueJob(new ExtoleAudienceSyncQueueable(cfg.Config_Key__c));
        }
    }

    /** Idempotent: schedule the hourly tick if not already registered. */
    public static void ensureScheduled() {
        List<CronTrigger> existing = [
            SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME LIMIT 1
        ];
        if (!existing.isEmpty()) return;
        try {
            System.schedule(JOB_NAME, CRON_HOURLY, new ExtoleAudienceScheduler());
        } catch (Exception e) {
            System.debug('ExtoleAudienceScheduler.ensureScheduled: ' + e.getMessage());
        }
    }

    private static Boolean isInFlight(String state) {
        return state == 'PREPARING' || state == 'BUILDING' || state == 'VALIDATING';
    }

    private static Boolean isDue(Extole_Audience_Cfg__c cfg, DateTime now) {
        if (cfg.Last_Sync_At__c == null) return true;
        Long elapsedMin = (now.getTime() - cfg.Last_Sync_At__c.getTime()) / 60000;
        if (cfg.Sync_Cadence__c == 'Hourly') return elapsedMin >= 50;     // ~1h buffer
        if (cfg.Sync_Cadence__c == 'Daily')  return elapsedMin >= 1380;   // ~23h
        if (cfg.Sync_Cadence__c == 'Weekly') return elapsedMin >= 9840;   // ~6d 20h
        return false;
    }
}
