public class ExtoleSyncJob implements Schedulable {

    // ─────────────────────────────────────────────────────────────────────────
    // Schedulable entry point
    // ─────────────────────────────────────────────────────────────────────────

    public void execute(SchedulableContext ctx) {
        System.debug('ExtoleSyncJob.execute: scheduled run triggered');
        System.enqueueJob(new SyncQueueable());
    }

    public class SyncQueueable implements Queueable, Database.AllowsCallouts {
        public void execute(QueueableContext ctx) {
            ExtoleSyncJob.performSync('Scheduled');
        }
    }

    // Called by ExtoleController.triggerSync() for on-demand manual syncs.
    // Returns the number of configs that failed in this run.
    public static Integer runNow() {
        System.debug('ExtoleSyncJob.runNow: manual sync triggered');
        return performSync('Manual');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core sync logic
    // ─────────────────────────────────────────────────────────────────────────

    @TestVisible
    private static Integer performSync(String triggerType) {
        String batchId = String.valueOf(System.currentTimeMillis())
                       + '-' + UserInfo.getUserId().left(8);
        System.debug('ExtoleSyncJob.performSync: batchId=' + batchId);

        // Load settings (read-only reference — never upsert this object back directly,
        // use writeSyncFields() below to avoid clobbering user-configured fields)
        Extole_App_Settings__c settings = Extole_App_Settings__c.getOrgDefaults();
        if (settings == null) settings = new Extole_App_Settings__c();
        Boolean debugEnabled = settings.Debug_Logging_Enabled__c == true;
        Integer historyDepth = settings.History_Depth__c != null
            ? (Integer) settings.History_Depth__c : 30;

        // Load active configs
        List<Extole_Report_Config__c> configs = [
            SELECT Id, Name, Report_Name__c, Report_Type__c, Executor_Type__c,
                   Display_Label__c, Value_Column__c, Aggregation__c, Chart_Type__c,
                   Data_Mode__c, Date_Range__c, Display_Order__c,
                   Parameter_Overrides_JSON__c, Active__c, Comparison_Period__c
            FROM Extole_Report_Config__c
            WHERE Active__c = true
        ];
        System.debug('ExtoleSyncJob: found ' + configs.size() + ' active configs');

        if (configs.isEmpty()) {
            // No active configs — delete all snapshots and return
            List<Extole_Report_Snapshot__c> allSnaps = [SELECT Id FROM Extole_Report_Snapshot__c];
            if (!allSnaps.isEmpty()) delete allSnaps;
            writeSyncFields(settings.Id, System.now(), null);
            return 0;
        }

        // ── Group configs by runner ID ─────────────────────────────────────
        Map<String, List<Extole_Report_Config__c>> configsByRunner =
            new Map<String, List<Extole_Report_Config__c>>();
        Set<String> activeConfigIds = new Set<String>();

        for (Extole_Report_Config__c cfg : configs) {
            activeConfigIds.add(cfg.Id);
            String rid = cfg.Report_Type__c;
            if (!configsByRunner.containsKey(rid)) {
                configsByRunner.put(rid, new List<Extole_Report_Config__c>());
            }
            configsByRunner.get(rid).add(cfg);
        }

        // ── Load existing snapshots ────────────────────────────────────────
        Map<String, Extole_Report_Snapshot__c> existingByConfigId =
            new Map<String, Extole_Report_Snapshot__c>();
        for (Extole_Report_Snapshot__c snap : [
            SELECT Id, Config_Id__c, As_Of_Date__c, Time_Series_JSON__c,
                   Report_Id__c, Value__c, View_URL__c, Client_Id__c
            FROM Extole_Report_Snapshot__c
            WHERE Config_Id__c IN :activeConfigIds
        ]) {
            existingByConfigId.put(snap.Config_Id__c, snap);
        }

        // ── Parse existing time series and find last known date per config ─
        Map<String, List<Map<String, Object>>> seriesByConfigId =
            new Map<String, List<Map<String, Object>>>();
        Map<String, Long> lastDateMsByConfigId = new Map<String, Long>();

        for (String configId : activeConfigIds) {
            Extole_Report_Snapshot__c snap = existingByConfigId.get(configId);
            List<Map<String, Object>> series = snap != null
                ? parseTimeSeries(snap.Time_Series_JSON__c)
                : new List<Map<String, Object>>();
            seriesByConfigId.put(configId, series);
            lastDateMsByConfigId.put(configId, getLastSeriesDateMs(series));
        }

        // ── Callout budget ─────────────────────────────────────────────────
        // 1 list call per runner + N download calls per runner, budget = 90
        Integer numRunners = configsByRunner.size();
        Integer downloadBudget = 90 - numRunners;
        Integer effectiveDepth = Math.max(1, Math.min(historyDepth, downloadBudget / numRunners));
        System.debug('ExtoleSyncJob: numRunners=' + numRunners
            + ' effectiveDepth=' + effectiveDepth);

        // ── Per-runner: list reports, download new ones ────────────────────
        // runnerDownloads: runnerId -> List of {reportId, createdAt, createdAtMs,
        //                                       viewUrl, clientId, rawJson}
        Map<String, List<Map<String, Object>>> runnerDownloads =
            new Map<String, List<Map<String, Object>>>();

        List<Extole_Sync_Log__c>  syncLogs  = new List<Extole_Sync_Log__c>();
        List<Extole_Debug_Log__c> debugLogs = new List<Extole_Debug_Log__c>();
        Integer consecutiveFailCount = 0;
        String  lastError            = '';
        Set<String> failedRunnerIds  = new Set<String>();

        Http http = new Http();

        for (String runnerId : configsByRunner.keySet()) {
            List<Extole_Report_Config__c> runnerCfgs = configsByRunner.get(runnerId);

            // Earliest last-date across all configs for this runner
            // (most aggressive cutoff = most data needed)
            Long runnerCutoffMs = 9999999999999L; // sentinel: will be replaced by real min date
            for (Extole_Report_Config__c cfg : runnerCfgs) {
                Long d = lastDateMsByConfigId.get(cfg.Id);
                if (d == null || d < 0L) {
                    runnerCutoffMs = -1L; // new config — need full history
                    break;
                }
                if (d < runnerCutoffMs) runnerCutoffMs = d;
            }

            // ── Step 1: List reports for this runner ──────────────────────
            List<Map<String, Object>> completedReports = new List<Map<String, Object>>();
            String listError = '';
            Integer listHttpStatus = 0;

            try {
                String listUrl = 'callout:Extole_API/v6/report-runners/'
                    + runnerId + '/reports?limit=' + effectiveDepth;
                HttpRequest listReq = new HttpRequest();
                listReq.setEndpoint(listUrl);
                listReq.setMethod('GET');
                listReq.setTimeout(30000);
                HttpResponse listRes = http.send(listReq);
                listHttpStatus = listRes.getStatusCode();

                System.debug('ExtoleSyncJob /reports HTTP ' + listRes.getStatusCode()
                    + ' runner=' + runnerId);

                if (debugEnabled) {
                    debugLogs.add(makeDebugLog(
                        runnerId, 'HTTP_RESPONSE',
                        'GET /reports | HTTP ' + listRes.getStatusCode() + ' | '
                        + listRes.getBody().left(500), batchId
                    ));
                }

                if (listRes.getStatusCode() != 200) {
                    listError = 'List reports HTTP ' + listRes.getStatusCode()
                        + ': ' + listRes.getBody().left(200);
                } else {
                    List<Object> raw = (List<Object>) JSON.deserializeUntyped(listRes.getBody());
                    // API returns newest first; collect DONE ones, then reverse to oldest-first
                    List<Map<String, Object>> doneReports = new List<Map<String, Object>>();
                    for (Object r : raw) {
                        Map<String, Object> rpt = (Map<String, Object>) r;
                        if (rpt.get('status') == 'DONE') doneReports.add(rpt);
                    }
                    for (Integer i = doneReports.size() - 1; i >= 0; i--) {
                        completedReports.add(doneReports[i]);
                    }
                }
            } catch (Exception e) {
                listError = e.getMessage();
                System.debug('ExtoleSyncJob: list reports failed for runner ' + runnerId
                    + ': ' + listError);
            }

            if (!String.isBlank(listError)) {
                // Mark all configs for this runner as failed in the sync log
                for (Extole_Report_Config__c cfg : runnerCfgs) {
                    consecutiveFailCount++;
                    lastError = listError;
                    Extole_Sync_Log__c logEntry = new Extole_Sync_Log__c();
                    logEntry.Report_Name__c      = cfg.Report_Name__c;
                    logEntry.Status__c           = 'FAILED';
                    logEntry.Trigger_Type__c     = triggerType;
                    logEntry.Sync_Timestamp__c   = System.now();
                    logEntry.HTTP_Status_Code__c = listHttpStatus > 0 ? listHttpStatus : null;
                    logEntry.Error_Message__c    = listError.left(255);
                    logEntry.Sync_Batch_Id__c    = batchId;
                    syncLogs.add(logEntry);
                }
                // 404 means the runner no longer exists in Extole — mark snapshots SOURCE_UNAVAILABLE
                // so the dashboard tile can surface a clear "Source Unavailable" state instead of
                // showing stale data silently.
                if (listHttpStatus == 404) {
                    Set<String> cfgIds = new Set<String>();
                    for (Extole_Report_Config__c cfg : runnerCfgs) cfgIds.add(cfg.Id);
                    List<Extole_Report_Snapshot__c> unavailSnaps = [
                        SELECT Id, Config_Status__c FROM Extole_Report_Snapshot__c
                        WHERE Config_Id__c IN :cfgIds
                    ];
                    if (!unavailSnaps.isEmpty()) {
                        for (Extole_Report_Snapshot__c s : unavailSnaps) {
                            s.Config_Status__c = 'SOURCE_UNAVAILABLE';
                        }
                        update unavailSnaps;
                    }
                }
                failedRunnerIds.add(runnerId);
                runnerDownloads.put(runnerId, new List<Map<String, Object>>());
                continue;
            }

            // ── Step 2: Download reports newer than the runner cutoff ──────
            List<Map<String, Object>> downloaded = new List<Map<String, Object>>();

            for (Map<String, Object> rpt : completedReports) {
                String reportId = rpt.get('report_id') != null
                    ? (String) rpt.get('report_id')
                    : rpt.get('id') != null ? (String) rpt.get('id') : null;
                if (String.isBlank(reportId)) continue;

                String createdAt = rpt.get('created_at') != null
                    ? (String) rpt.get('created_at') : '';
                Long createdAtMs = parseDateMs(createdAt);

                // Skip if already have data at or before this report (incremental)
                if (runnerCutoffMs > 0 && createdAtMs > 0 && createdAtMs <= runnerCutoffMs) {
                    continue;
                }

                // Download report data
                String rawJson = null;
                try {
                    HttpRequest dlReq = new HttpRequest();
                    dlReq.setEndpoint('callout:Extole_API/v4/reports/' + reportId + '/download.json');
                    dlReq.setMethod('GET');
                    dlReq.setTimeout(30000);
                    HttpResponse dlRes = http.send(dlReq);

                    System.debug('ExtoleSyncJob download HTTP ' + dlRes.getStatusCode()
                        + ' reportId=' + reportId);

                    if (debugEnabled) {
                        debugLogs.add(makeDebugLog(
                            runnerId, 'HTTP_RESPONSE',
                            'GET /download.json | reportId=' + reportId
                            + ' | HTTP ' + dlRes.getStatusCode()
                            + ' | len=' + dlRes.getBody().length(), batchId
                        ));
                    }

                    if (dlRes.getStatusCode() == 200) rawJson = dlRes.getBody();
                } catch (Exception e) {
                    System.debug('ExtoleSyncJob: download failed for report '
                        + reportId + ': ' + e.getMessage());
                }

                if (rawJson == null) continue;

                downloaded.add(new Map<String, Object>{
                    'reportId'    => reportId,
                    'createdAt'   => createdAt,
                    'createdAtMs' => createdAtMs,
                    'viewUrl'     => rpt.get('view_url')  != null ? rpt.get('view_url')  : '',
                    'clientId'    => rpt.get('client_id') != null ? rpt.get('client_id') : '',
                    'rawJson'     => rawJson
                });
            }

            runnerDownloads.put(runnerId, downloaded);
            System.debug('ExtoleSyncJob: runner=' + runnerId
                + ' downloaded=' + downloaded.size() + ' new reports');
        }

        // ── Process each config → build/update snapshot ───────────────────
        List<Extole_Report_Snapshot__c> snapshotsToUpsert = new List<Extole_Report_Snapshot__c>();

        for (Extole_Report_Config__c cfg : configs) {
            String runnerId = cfg.Report_Type__c;
            // Runner-level failure already logged above — skip per-config processing
            if (failedRunnerIds.contains(runnerId)) continue;
            List<Map<String, Object>> downloads = runnerDownloads.get(runnerId);
            if (downloads == null) downloads = new List<Map<String, Object>>();

            // Working copy of the time series (oldest first)
            List<Map<String, Object>> series = new List<Map<String, Object>>();
            series.addAll(seriesByConfigId.get(cfg.Id));
            Long configLastDateMs = lastDateMsByConfigId.get(cfg.Id);
            if (configLastDateMs == null) configLastDateMs = -1L;

            String latestExtractedVal = null;
            String latestReportId     = null;
            String latestViewUrl      = '';
            String latestClientId     = '';
            Long   latestReportDateMs = -1L;
            String statusStr = 'SUCCESS';
            String errMsg    = '';

            try {
                // Merge new downloads into this config's time series
                for (Map<String, Object> dl : downloads) {
                    Long dlDateMs = (Long) dl.get('createdAtMs');

                    // Skip data points already in this config's series
                    if (dlDateMs != null && dlDateMs > 0 && configLastDateMs > 0
                            && dlDateMs <= configLastDateMs) {
                        continue;
                    }

                    String rawJson = (String) dl.get('rawJson');
                    String val = extractValue(rawJson, cfg.Value_Column__c, cfg.Aggregation__c);

                    // Use Extole's createdAt if present; fall back to sync time so
                    // the series always has parseable dates for comparison period.
                    String pointDate = (String) dl.get('createdAt');
                    if (String.isBlank(pointDate)) {
                        pointDate = System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
                    }
                    series.add(new Map<String, Object>{
                        'date'  => pointDate,
                        'value' => val != null ? val : '0'
                    });

                    latestExtractedVal = val;
                    latestReportId     = (String) dl.get('reportId');
                    latestViewUrl      = (String) dl.get('viewUrl');
                    latestClientId     = (String) dl.get('clientId');
                    latestReportDateMs = dlDateMs != null ? dlDateMs : -1L;
                }

                // Fall back to existing value if nothing new was downloaded
                Extole_Report_Snapshot__c existing = existingByConfigId.get(cfg.Id);
                if (latestExtractedVal == null && existing != null) {
                    latestExtractedVal = existing.Value__c;
                }

                // Trim to history depth (keep most recent N points)
                if (series.size() > historyDepth) {
                    List<Map<String, Object>> trimmed = new List<Map<String, Object>>();
                    for (Integer i = series.size() - historyDepth; i < series.size(); i++) {
                        trimmed.add(series[i]);
                    }
                    series = trimmed;
                }

                // Compute Prior_Period_Value__c from comparison period
                String priorVal = null;
                Integer compDays = parseComparisonDays(cfg.Comparison_Period__c);
                if (compDays > 0 && !series.isEmpty()) {
                    priorVal = findClosestSeriesValue(series, System.now().addDays(-compDays));
                    System.debug('ExtoleSyncJob: priorVal=' + priorVal
                        + ' compDays=' + compDays + ' for ' + cfg.Report_Name__c);
                }

                // Build snapshot record (update existing or create new)
                Extole_Report_Snapshot__c snap = existing != null
                    ? existing : new Extole_Report_Snapshot__c();

                snap.Name             = cfg.Display_Label__c != null
                                            ? cfg.Display_Label__c : cfg.Report_Name__c;
                snap.Display_Label__c = cfg.Display_Label__c;
                snap.Value__c         = latestExtractedVal;
                snap.Prior_Period_Value__c = priorVal;
                snap.Time_Series_JSON__c   = series.isEmpty() ? null : JSON.serialize(series);
                snap.Report_Name__c   = cfg.Report_Name__c;
                snap.Executor_Type__c = cfg.Executor_Type__c;
                // As_Of_Date reflects when SFDC last successfully synced, not when
                // Extole generated the report — keeps the tile footer date current.
                snap.As_Of_Date__c = System.now();
                // Date_Range__c stores the comparison period label for the tile trendText
                snap.Date_Range__c    = cfg.Comparison_Period__c != null
                                            ? cfg.Comparison_Period__c : cfg.Date_Range__c;
                snap.Display_Order__c = cfg.Display_Order__c;
                snap.Chart_Type__c    = cfg.Chart_Type__c;
                snap.Config_Id__c     = cfg.Id;
                snap.Config_Status__c = 'ACTIVE';
                snap.Next_Expected_Sync__c = calcNextExpectedSync(settings.Sync_Cadence__c);

                // Only overwrite connection metadata when we actually downloaded something
                if (latestReportId != null) {
                    snap.View_URL__c      = latestViewUrl;
                    snap.Report_Id__c     = latestReportId;
                    snap.Client_Id__c     = latestClientId;
                    snap.Schedule_URL__c  = 'https://my.extole.com/reports?user_id='
                        + latestClientId + '#/schedules/' + runnerId;
                }

                snapshotsToUpsert.add(snap);

                if (debugEnabled) {
                    String firstDate = !series.isEmpty() ? (String) series[0].get('date') : 'n/a';
                    String lastDate  = series.size() > 1  ? (String) series[series.size()-1].get('date') : 'n/a';
                    debugLogs.add(makeDebugLog(
                        cfg.Report_Name__c, 'VALUE_EXTRACTED',
                        'value=' + latestExtractedVal
                            + ' priorVal=' + priorVal
                            + ' seriesLen=' + series.size()
                            + ' firstDate=' + firstDate
                            + ' lastDate=' + lastDate, batchId
                    ));
                }

            } catch (Exception e) {
                consecutiveFailCount++;
                errMsg    = e.getMessage();
                lastError = errMsg;
                statusStr = 'FAILED';
                System.debug('ExtoleSyncJob ERROR for config ' + cfg.Report_Name__c
                    + ': ' + errMsg);
            }

            // Always write a sync log entry
            Extole_Sync_Log__c logEntry = new Extole_Sync_Log__c();
            logEntry.Report_Name__c      = cfg.Report_Name__c;
            logEntry.Date_Range__c       = String.isNotBlank(cfg.Comparison_Period__c)
                                               ? cfg.Comparison_Period__c : cfg.Date_Range__c;
            logEntry.Executor_Type__c    = cfg.Executor_Type__c;
            logEntry.Status__c           = statusStr;
            logEntry.Trigger_Type__c     = triggerType;
            logEntry.Sync_Timestamp__c   = System.now();
            logEntry.Value_Extracted__c  = latestExtractedVal;
            logEntry.HTTP_Status_Code__c = statusStr == 'SUCCESS' ? 200 : null;
            logEntry.Poll_Attempts__c    = 0;
            logEntry.Error_Message__c    = errMsg.length() > 255 ? errMsg.left(255) : errMsg;
            logEntry.Sync_Batch_Id__c    = batchId;
            syncLogs.add(logEntry);
        }

        // ── Upsert snapshots ──────────────────────────────────────────────
        if (!snapshotsToUpsert.isEmpty()) {
            upsert snapshotsToUpsert;
            System.debug('ExtoleSyncJob: upserted ' + snapshotsToUpsert.size() + ' snapshots');
        }

        // ── Orphan reconciliation — delete snapshots for removed configs ──────
        Set<String> orphanCheckSet = new Set<String>(activeConfigIds);
        orphanCheckSet.add('000000000000000000');
        List<Extole_Report_Snapshot__c> toDelete = [
            SELECT Id FROM Extole_Report_Snapshot__c
            WHERE Config_Id__c NOT IN :orphanCheckSet
        ];
        if (!toDelete.isEmpty()) {
            delete toDelete;
            System.debug('ExtoleSyncJob: deleted ' + toDelete.size() + ' orphaned snapshots');
        }

        // ── Bulk insert logs ──────────────────────────────────────────────
        if (!syncLogs.isEmpty())  insert syncLogs;
        if (!debugLogs.isEmpty()) insert debugLogs;

        // ── Log retention: delete records older than 30 days ──────────────
        DateTime cutoff = System.now().addDays(-30);
        List<Extole_Sync_Log__c> oldSyncLogs = [
            SELECT Id FROM Extole_Sync_Log__c WHERE Sync_Timestamp__c < :cutoff
        ];
        if (!oldSyncLogs.isEmpty()) delete oldSyncLogs;
        List<Extole_Debug_Log__c> oldDebugLogs = [
            SELECT Id FROM Extole_Debug_Log__c WHERE Log_Timestamp__c < :cutoff
        ];
        if (!oldDebugLogs.isEmpty()) delete oldDebugLogs;
        List<Extole_Event_Log__c> oldEventLogs = [
            SELECT Id FROM Extole_Event_Log__c WHERE Timestamp__c < :cutoff
        ];
        if (!oldEventLogs.isEmpty()) delete oldEventLogs;

        // ── Update Last_Sync_Timestamp + Consecutive_Failure_Count ──────────
        Integer prevConsecutive = settings.Consecutive_Failure_Count__c != null
            ? (Integer) settings.Consecutive_Failure_Count__c : 0;
        Integer newConsecutive = consecutiveFailCount > 0 ? prevConsecutive + 1 : 0;
        writeSyncFields(settings.Id, System.now(), newConsecutive);

        // ── Failure notification ──────────────────────────────────────────
        if (consecutiveFailCount > 0) {
            Integer notifyAfter  = settings.Notify_After_N_Failures__c != null
                ? (Integer) settings.Notify_After_N_Failures__c : 2;
            Boolean notifyEnabled = settings.Notify_On_Sync_Failure__c == true;

            if (notifyEnabled && newConsecutive >= notifyAfter
                    && String.isNotBlank(settings.Failure_Notification_Email__c)) {
                sendFailureEmail(settings, lastError, batchId);
            }
        }

        return consecutiveFailCount;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Value extraction
    // ─────────────────────────────────────────────────────────────────────────

    public static String extractValue(String rawJson, String valueColumn, String aggregation) {
        if (String.isBlank(rawJson)) return null;

        List<Object> rows;
        try {
            rows = (List<Object>) JSON.deserializeUntyped(rawJson);
        } catch (Exception e) {
            System.debug('ExtoleSyncJob.extractValue: could not parse JSON: ' + e.getMessage());
            return null;
        }

        if (rows == null || rows.isEmpty()) return null;

        if (aggregation == 'COUNT') {
            return String.valueOf(rows.size());
        }

        if (String.isBlank(valueColumn)) return null;

        Map<String, Object> firstRow = (Map<String, Object>) rows[0];
        System.debug('ExtoleSyncJob.extractValue: column="' + valueColumn
            + '" | columns=' + firstRow.keySet());

        if (aggregation == 'FIRST_ROW') {
            Object val = firstRow.get(valueColumn);
            return val != null ? String.valueOf(val) : null;
        }

        if (aggregation == 'SUM') {
            Decimal total = 0;
            for (Object rowObj : rows) {
                Map<String, Object> row = (Map<String, Object>) rowObj;
                Object val = row.get(valueColumn);
                if (val != null) {
                    try {
                        total += Decimal.valueOf(String.valueOf(val));
                    } catch (Exception e) {
                        System.debug('ExtoleSyncJob.extractValue SUM: non-numeric value=' + val);
                    }
                }
            }
            return String.valueOf(total);
        }

        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Time series helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static List<Map<String, Object>> parseTimeSeries(String jsonStr) {
        if (String.isBlank(jsonStr)) return new List<Map<String, Object>>();
        try {
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(jsonStr);
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            for (Object o : raw) result.add((Map<String, Object>) o);
            return result;
        } catch (Exception e) {
            return new List<Map<String, Object>>();
        }
    }

    private static Long getLastSeriesDateMs(List<Map<String, Object>> series) {
        if (series == null || series.isEmpty()) return -1L;
        Long maxMs = -1L;
        for (Map<String, Object> pt : series) {
            Long ms = parseDateMs((String) pt.get('date'));
            if (ms > maxMs) maxMs = ms;
        }
        return maxMs;
    }

    private static Long parseDateMs(String isoDate) {
        if (String.isBlank(isoDate)) return -1L;
        try {
            // Normalise to "YYYY-MM-DD HH:MM:SS" for DateTime.valueOfGmt().
            // Handles Z, +HH:MM, -HH:MM, +HHMM, milliseconds — any ISO 8601 variant.
            String cleaned = isoDate.replace('T', ' ');
            // First 19 chars is always YYYY-MM-DD HH:MM:SS — drop everything after
            if (cleaned.length() > 19) cleaned = cleaned.substring(0, 19);
            return DateTime.valueOfGmt(cleaned).getTime();
        } catch (Exception e) {
            return -1L;
        }
    }

    // Finds the time series value whose date is closest to targetDate.
    // Falls back to the oldest point in the series if no dates are parseable.
    private static String findClosestSeriesValue(
        List<Map<String, Object>> series, DateTime targetDate
    ) {
        Long targetMs  = targetDate.getTime();
        Long minDiff   = null;
        String closest = null;

        for (Map<String, Object> pt : series) {
            Long ptMs = parseDateMs((String) pt.get('date'));
            if (ptMs < 0) continue;
            Long diff = Math.abs(targetMs - ptMs);
            if (minDiff == null || diff < minDiff) {
                minDiff = diff;
                closest = (String) pt.get('value');
            }
        }
        // If no dates were parseable, fall back to the oldest point in the series.
        // This handles legacy series with blank dates and gives a meaningful baseline.
        if (closest == null && !series.isEmpty()) {
            closest = (String) series[0].get('value');
        }
        return closest;
    }

    private static Integer parseComparisonDays(String period) {
        if ('1 day'  == period) return 1;
        if ('7 days'       == period) return 7;
        if ('14 days'      == period) return 14;
        if ('30 days'      == period) return 30;
        if ('90 days'      == period) return 90;
        return 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utility: next expected sync calculation
    // ─────────────────────────────────────────────────────────────────────────

    public static DateTime calcNextExpectedSync(String cadence) {
        DateTime now = System.now();
        if (cadence == 'Every 30min') return now.addMinutes(30);
        if (cadence == 'Every 6hrs')  return now.addHours(6);
        if (cadence == 'Every 12hrs') return now.addHours(12);
        return now.addHours(24); // Nightly default
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utility: debug log factory
    // ─────────────────────────────────────────────────────────────────────────

    private static Extole_Debug_Log__c makeDebugLog(
        String reportName, String eventType, String detail, String batchId
    ) {
        Extole_Debug_Log__c log = new Extole_Debug_Log__c();
        log.Report_Name__c   = reportName;
        log.Log_Timestamp__c = System.now();
        log.Event_Type__c    = eventType;
        log.Detail__c        = detail != null && detail.length() > 131072
                                   ? detail.left(131072) : detail;
        log.Sync_Batch_Id__c = batchId;
        return log;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Targeted settings write — only touches sync-internal fields so user-
    // configured fields (Notify, email, cadence, etc.) are never clobbered
    // ─────────────────────────────────────────────────────────────────────────

    private static void writeSyncFields(Id settingsId, DateTime lastSync, Integer failCount) {
        Extole_App_Settings__c upd;
        if (settingsId != null) {
            // Read the full record first so the update never clobbers user-configured fields.
            // Assigning only 2 fields to a new sObject(Id=x) can behave unexpectedly with
            // Hierarchy Custom Settings upsert — reading first is the safe pattern.
            List<Extole_App_Settings__c> rows = [
                SELECT Id, Last_Sync_Timestamp__c, Consecutive_Failure_Count__c,
                       Notify_On_Sync_Failure__c, Notify_After_N_Failures__c,
                       Failure_Notification_Email__c, Sync_Cadence__c,
                       Debug_Logging_Enabled__c, History_Depth__c,
                       Show_List_View__c, List_View_Field__c,
                       List_View_Value__c, List_View_Start_Date__c,
                       Scheduled_Job_Id__c
                FROM Extole_App_Settings__c
                WHERE Id = :settingsId
                LIMIT 1
            ];
            upd = rows.isEmpty() ? new Extole_App_Settings__c() : rows[0];
        } else {
            upd = new Extole_App_Settings__c();
        }
        upd.Last_Sync_Timestamp__c       = lastSync;
        upd.Consecutive_Failure_Count__c = failCount;
        upsert upd;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Failure notification email
    // ─────────────────────────────────────────────────────────────────────────

    private static void sendFailureEmail(
        Extole_App_Settings__c settings, String lastError, String batchId
    ) {
        try {
            String orgName     = UserInfo.getOrganizationName();
            String lastSuccess = settings.Last_Sync_Timestamp__c != null
                ? String.valueOf(settings.Last_Sync_Timestamp__c) : 'Never';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[]{ settings.Failure_Notification_Email__c });
            mail.setSaveAsActivity(false);
            mail.setSubject('[Extole for Salesforce] Sync failure — action required');
            mail.setPlainTextBody(
                'Org: '                   + orgName      + '\n' +
                'Last successful sync: '  + lastSuccess  + '\n' +
                'Error: '                 + lastError     + '\n' +
                'Batch ID: '              + batchId       + '\n\n' +
                'Please review the sync log in the Extole App Settings tab for details.'
            );
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
            System.debug('ExtoleSyncJob.sendFailureEmail: sent to ' + settings.Failure_Notification_Email__c);

            // Record the send attempt in the debug log so it's visible without enabling full debug logging
            insert new Extole_Debug_Log__c(
                Report_Name__c   = 'SYSTEM',
                Log_Timestamp__c = System.now(),
                Event_Type__c    = 'EMAIL_SENT',
                Detail__c        = 'Failure notification sent to: ' + settings.Failure_Notification_Email__c
                                 + ' | Error: ' + lastError.left(200),
                Sync_Batch_Id__c = batchId
            );
        } catch (Exception e) {
            System.debug('ExtoleSyncJob.sendFailureEmail ERROR: ' + e.getMessage());
            insert new Extole_Debug_Log__c(
                Report_Name__c   = 'SYSTEM',
                Log_Timestamp__c = System.now(),
                Event_Type__c    = 'EMAIL_ERROR',
                Detail__c        = 'Failed to send notification to: ' + settings.Failure_Notification_Email__c
                                 + ' | Exception: ' + e.getMessage(),
                Sync_Batch_Id__c = batchId
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Schedule management
    // Aborts any existing job stored in settings, then registers a new one
    // for the given cadence. Returns the new CronTrigger ID (or null if cadence
    // is blank/None). Called by ExtoleController.saveSettings so that changing
    // the cadence slider immediately re-wires the scheduled job.
    // ─────────────────────────────────────────────────────────────────────────

    public static String scheduleJob(String cadence) {
        // Abort ALL active ExtoleSync_* jobs — query by name so stale stored IDs
        // don't leave orphan jobs behind when the ID in settings is out of date.
        List<CronTrigger> existingJobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'ExtoleSync_%'
              AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
        ];
        for (CronTrigger job : existingJobs) {
            try {
                System.abortJob(job.Id);
                System.debug('ExtoleSyncJob.scheduleJob: aborted job ' + job.Id);
            } catch (Exception e) {
                System.debug('ExtoleSyncJob.scheduleJob: could not abort job ' + job.Id + ': ' + e.getMessage());
            }
        }

        if (String.isBlank(cadence) || cadence == 'None') {
            System.debug('ExtoleSyncJob.scheduleJob: cadence=None, no job scheduled');
            return null;
        }

        String ts = String.valueOf(System.currentTimeMillis());

        // Every 30min requires two jobs (:00 and :30) — Salesforce cron does not support 0/30 syntax
        if (cadence == 'Every 30min') {
            String id1 = System.schedule('ExtoleSync_30m_top_' + ts, '0 0 * * * ?', new ExtoleSyncJob());
            String id2 = System.schedule('ExtoleSync_30m_bot_' + ts, '0 30 * * * ?', new ExtoleSyncJob());
            System.debug('ExtoleSyncJob.scheduleJob: scheduled Every 30min id1=' + id1 + ' id2=' + id2);
            return id1;
        }

        String cronExpr;
        if      (cadence == 'Every 6hrs')  cronExpr = '0 0 0/6 * * ?';
        else if (cadence == 'Every 12hrs') cronExpr = '0 0 0/12 * * ?';
        else                               cronExpr = '0 0 2 * * ?'; // Nightly at 2 AM

        String jobName = 'ExtoleSync_' + ts;
        String jobId   = System.schedule(jobName, cronExpr, new ExtoleSyncJob());
        System.debug('ExtoleSyncJob.scheduleJob: scheduled id=' + jobId + ' cadence=' + cadence);
        return jobId;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Custom exception
    // ─────────────────────────────────────────────────────────────────────────

    public class ExtoleSyncException extends Exception {}
}
