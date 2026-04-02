// Check all ExtoleSync scheduled jobs and their states
List<CronTrigger> jobs = [
    SELECT Id, CronJobDetail.Name, State, NextFireTime, PreviousFireTime, TimesTriggered
    FROM CronTrigger
    WHERE CronJobDetail.Name LIKE 'ExtoleSync_%'
];
System.debug('=== ExtoleSync CronTriggers (' + jobs.size() + ') ===');
for (CronTrigger j : jobs) {
    System.debug('Id=' + j.Id
        + ' | Name=' + j.CronJobDetail.Name
        + ' | State=' + j.State
        + ' | NextFire=' + j.NextFireTime
        + ' | PrevFire=' + j.PreviousFireTime
        + ' | TimesTriggered=' + j.TimesTriggered);
}

// Check stored job ID in settings
Extole_App_Settings__c s = Extole_App_Settings__c.getOrgDefaults();
System.debug('=== Settings ===');
System.debug('Scheduled_Job_Id__c=' + (s != null ? s.Scheduled_Job_Id__c : 'null'));
System.debug('Sync_Cadence__c=' + (s != null ? s.Sync_Cadence__c : 'null'));
