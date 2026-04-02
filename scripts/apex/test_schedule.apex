try {
    String jobId = ExtoleSyncJob.scheduleJob('Every 30min');
    System.debug('scheduleJob SUCCESS: jobId=' + jobId);
    // Verify it's in CronTrigger
    List<CronTrigger> jobs = [
        SELECT Id, State, NextFireTime
        FROM CronTrigger
        WHERE CronJobDetail.Name LIKE 'ExtoleSync_%'
          AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
    ];
    System.debug('Active ExtoleSync jobs after schedule: ' + jobs.size());
    for (CronTrigger j : jobs) {
        System.debug('  Id=' + j.Id + ' State=' + j.State + ' NextFire=' + j.NextFireTime);
    }
} catch(Exception e) {
    System.debug('scheduleJob ERROR: ' + e.getMessage());
    System.debug('Stack: ' + e.getStackTraceString());
}
