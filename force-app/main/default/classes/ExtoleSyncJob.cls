global class ExtoleSyncJob implements Schedulable {

    // ─────────────────────────────────────────────────────────────────────────
    // Schedulable entry point
    // ─────────────────────────────────────────────────────────────────────────

    global void execute(SchedulableContext ctx) {
        System.debug('ExtoleSyncJob.execute: scheduled run triggered');
        performSync();
    }

    // Called by ExtoleController.triggerSync() for on-demand manual syncs
    public static void runNow() {
        System.debug('ExtoleSyncJob.runNow: manual sync triggered');
        performSync();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core sync logic
    // ─────────────────────────────────────────────────────────────────────────

    @TestVisible
    private static void performSync() {
        String batchId = String.valueOf(System.currentTimeMillis())
                       + '-' + UserInfo.getUserId().left(8);
        System.debug('ExtoleSyncJob.performSync: batchId=' + batchId);

        // Load settings
        Extole_App_Settings__c settings = Extole_App_Settings__c.getOrgDefaults();
        if (settings == null) {
            settings = new Extole_App_Settings__c();
        }
        Boolean debugEnabled = settings.Debug_Logging_Enabled__c == true;

        // Load active configs
        List<Extole_Report_Config__c> configs = [
            SELECT Id, Name, Report_Name__c, Report_Type__c, Executor_Type__c,
                   Display_Label__c, Value_Column__c, Aggregation__c, Chart_Type__c,
                   Data_Mode__c, Date_Range__c, Display_Order__c,
                   Parameter_Overrides_JSON__c, Active__c
            FROM Extole_Report_Config__c
            WHERE Active__c = true
        ];
        System.debug('ExtoleSyncJob: found ' + configs.size() + ' active configs');

        if (configs.isEmpty()) {
            System.debug('ExtoleSyncJob: no active configs — running orphan reconciliation then exiting');
            // Still run orphan reconciliation: all existing snapshots are orphaned
            Set<String> noActiveIds = new Set<String>{ '000000000000000000' };
            List<Extole_Report_Snapshot__c> allOrphans = [
                SELECT Id, Config_Status__c
                FROM Extole_Report_Snapshot__c
                WHERE Config_Id__c NOT IN :noActiveIds
                  AND Config_Status__c != 'ORPHANED'
            ];
            if (!allOrphans.isEmpty()) {
                for (Extole_Report_Snapshot__c s : allOrphans) {
                    s.Config_Status__c = 'ORPHANED';
                }
                update allOrphans;
                System.debug('ExtoleSyncJob: marked ' + allOrphans.size() + ' snapshots as ORPHANED (no active configs)');
            }
            // Update last sync timestamp and return
            settings.Last_Sync_Timestamp__c = System.now();
            upsert settings;
            return;
        }

        // Collect results for bulk DML at end
        List<Extole_Report_Snapshot__c> snapshotsToUpsert = new List<Extole_Report_Snapshot__c>();
        List<Extole_Sync_Log__c>         syncLogs          = new List<Extole_Sync_Log__c>();
        List<Extole_Debug_Log__c>        debugLogs         = new List<Extole_Debug_Log__c>();
        Set<String>                      activeConfigIds   = new Set<String>();
        Integer consecutiveFailCount = 0;
        String  lastError            = '';

        String[] dateRanges = new String[]{ 'Rolling 30', 'Rolling 90', 'YTD' };

        Http http = new Http();

        for (Extole_Report_Config__c config : configs) {
            activeConfigIds.add(config.Id);

            for (String dateRange : dateRanges) {
                String reportId   = null;
                String statusStr  = 'FAILED';
                String extractedVal = null;
                String errMsg     = '';
                Integer httpStatus  = 0;
                Integer pollAttempts = 0;
                String  viewUrl   = '';
                String  extRptId  = '';
                String  clientId  = '';

                // ── STEP 1: POST to trigger report ──────────────────────────
                try {
                    String drParam = toDateRangeParam(dateRange);
                    Map<String, Object> postBody = new Map<String, Object>{
                        'name'   => config.Report_Name__c,
                        'format' => 'JSON',
                        'parameters' => new Map<String, Object>{
                            'date_range' => drParam
                        }
                    };

                    // Merge parameter overrides if present
                    if (String.isNotBlank(config.Parameter_Overrides_JSON__c)) {
                        try {
                            Map<String, Object> overrides = (Map<String, Object>)
                                JSON.deserializeUntyped(config.Parameter_Overrides_JSON__c);
                            Map<String, Object> params = (Map<String, Object>) postBody.get('parameters');
                            params.putAll(overrides);
                        } catch (Exception ex) {
                            System.debug('ExtoleSyncJob: could not parse parameter overrides: ' + ex.getMessage());
                        }
                    }

                    String postBodyStr = JSON.serialize(postBody);
                    System.debug('ExtoleSyncJob POST /v4/reports body: ' + postBodyStr);

                    if (debugEnabled) {
                        debugLogs.add(makeDebugLog(
                            config.Report_Name__c, 'HTTP_REQUEST',
                            'POST /v4/reports | body: ' + postBodyStr, batchId
                        ));
                    }

                    HttpRequest postReq = new HttpRequest();
                    postReq.setEndpoint('callout:Extole_API/v4/reports');
                    postReq.setMethod('POST');
                    postReq.setHeader('Content-Type', 'application/json');
                    postReq.setBody(postBodyStr);
                    postReq.setTimeout(30000);

                    HttpResponse postRes = http.send(postReq);
                    httpStatus = postRes.getStatusCode();
                    System.debug('ExtoleSyncJob POST response HTTP ' + httpStatus
                        + ' body: ' + postRes.getBody());

                    if (debugEnabled) {
                        debugLogs.add(makeDebugLog(
                            config.Report_Name__c, 'HTTP_RESPONSE',
                            'POST /v4/reports | HTTP ' + httpStatus + ' | ' + postRes.getBody(), batchId
                        ));
                    }

                    if (httpStatus != 200 && httpStatus != 201 && httpStatus != 202) {
                        throw new ExtoleSyncException(
                            'POST /v4/reports failed HTTP ' + httpStatus + ': ' + postRes.getBody()
                        );
                    }

                    Map<String, Object> postResp = (Map<String, Object>)
                        JSON.deserializeUntyped(postRes.getBody());
                    reportId  = (String) postResp.get('report_id');
                    viewUrl   = postResp.get('view_url')  != null ? (String) postResp.get('view_url')  : '';
                    extRptId  = postResp.get('report_id') != null ? (String) postResp.get('report_id') : '';
                    clientId  = postResp.get('client_id') != null ? (String) postResp.get('client_id') : '';

                    // ── STEP 2: Poll for DONE ─────────────────────────────
                    Integer maxRetries = maxRetriesFor(config.Executor_Type__c);
                    String  pollStatus = (String) postResp.get('status');

                    while (pollAttempts < maxRetries && pollStatus != 'DONE' && pollStatus != 'FAILED') {
                        pollAttempts++;

                        HttpRequest pollReq = new HttpRequest();
                        pollReq.setEndpoint('callout:Extole_API/v4/reports/' + reportId);
                        pollReq.setMethod('GET');
                        pollReq.setTimeout(15000);

                        HttpResponse pollRes = http.send(pollReq);
                        Map<String, Object> pollResp = (Map<String, Object>)
                            JSON.deserializeUntyped(pollRes.getBody());
                        pollStatus = (String) pollResp.get('status');

                        // Capture view_url / client_id from poll response as well
                        if (pollResp.get('view_url')  != null) viewUrl  = (String) pollResp.get('view_url');
                        if (pollResp.get('client_id') != null) clientId = (String) pollResp.get('client_id');

                        System.debug('ExtoleSyncJob poll attempt=' + pollAttempts
                            + ' reportId=' + reportId + ' status=' + pollStatus);

                        if (debugEnabled) {
                            debugLogs.add(makeDebugLog(
                                config.Report_Name__c, 'POLL_ATTEMPT',
                                'attempt=' + pollAttempts + ' status=' + pollStatus
                                    + ' reportId=' + reportId, batchId
                            ));
                        }
                    }

                    if (pollStatus != 'DONE') {
                        throw new ExtoleSyncException(
                            'Report did not reach DONE after ' + pollAttempts
                            + ' attempts. Last status: ' + pollStatus
                        );
                    }

                    // ── STEP 3: Download ─────────────────────────────────
                    HttpRequest dlReq = new HttpRequest();
                    dlReq.setEndpoint('callout:Extole_API/v4/reports/' + reportId + '/download');
                    dlReq.setMethod('GET');
                    dlReq.setTimeout(30000);

                    HttpResponse dlRes = http.send(dlReq);
                    String rawJson = dlRes.getBody();
                    System.debug('ExtoleSyncJob download HTTP ' + dlRes.getStatusCode()
                        + ' length=' + rawJson.length());

                    // Log raw output BEFORE any parsing (key diagnostic)
                    if (debugEnabled) {
                        debugLogs.add(makeDebugLog(
                            config.Report_Name__c, 'RAW_OUTPUT',
                            'reportId=' + reportId + ' | ' + rawJson, batchId
                        ));
                    }

                    if (dlRes.getStatusCode() != 200) {
                        throw new ExtoleSyncException(
                            'Download failed HTTP ' + dlRes.getStatusCode() + ': ' + rawJson
                        );
                    }

                    // ── STEP 4: Extract value ────────────────────────────
                    extractedVal = extractValue(rawJson, config.Value_Column__c, config.Aggregation__c);
                    System.debug('ExtoleSyncJob extracted value=' + extractedVal
                        + ' for ' + config.Report_Name__c + '/' + dateRange);

                    if (debugEnabled) {
                        debugLogs.add(makeDebugLog(
                            config.Report_Name__c, 'VALUE_EXTRACTED',
                            'valueColumn=' + config.Value_Column__c
                                + ' aggregation=' + config.Aggregation__c
                                + ' value=' + extractedVal, batchId
                        ));
                    }

                    // ── STEP 5: Time series (if applicable) ──────────────
                    String timeSeriesJson = null;
                    String priorValue     = null;
                    if (config.Data_Mode__c == 'Time Series') {
                        timeSeriesJson = buildTimeSeriesJson(rawJson, config.Value_Column__c);
                        // Prior period: run a second report for the prior window
                        priorValue = runPriorPeriod(
                            config, dateRange, batchId, debugEnabled, debugLogs, http
                        );
                        System.debug('ExtoleSyncJob time series built, priorValue=' + priorValue);
                    }

                    // ── STEP 6: Build snapshot record ────────────────────
                    // Query-then-upsert pattern keyed on (Config_Id__c, Date_Range__c)
                    Extole_Report_Snapshot__c snap = new Extole_Report_Snapshot__c();
                    snap.Name               = (config.Display_Label__c != null ? config.Display_Label__c : config.Report_Name__c) + ' – ' + dateRange;
                    snap.Display_Label__c   = config.Display_Label__c;
                    snap.Value__c           = extractedVal;
                    snap.Prior_Period_Value__c = priorValue;
                    snap.Time_Series_JSON__c   = timeSeriesJson;
                    snap.Report_Name__c     = config.Report_Name__c;
                    snap.Executor_Type__c   = config.Executor_Type__c;
                    snap.As_Of_Date__c      = System.now();
                    snap.Date_Range__c      = dateRange;
                    snap.Display_Order__c   = config.Display_Order__c;
                    snap.Chart_Type__c      = config.Chart_Type__c;
                    snap.Config_Id__c       = config.Id;
                    snap.View_URL__c        = viewUrl;
                    snap.Report_Id__c       = extRptId;
                    snap.Client_Id__c       = clientId;
                    snap.Config_Status__c   = 'ACTIVE';

                    // Calculate Next_Expected_Sync
                    snap.Next_Expected_Sync__c = calcNextExpectedSync(settings.Sync_Cadence__c);

                    snapshotsToUpsert.add(snap);
                    statusStr = 'SUCCESS';

                } catch (Exception e) {
                    consecutiveFailCount++;
                    errMsg = e.getMessage();
                    lastError = errMsg;
                    System.debug('ExtoleSyncJob ERROR for ' + config.Report_Name__c
                        + '/' + dateRange + ': ' + errMsg);
                    if (debugEnabled) {
                        debugLogs.add(makeDebugLog(
                            config.Report_Name__c, 'SYNC_ERROR',
                            'dateRange=' + dateRange + ' error=' + errMsg, batchId
                        ));
                    }
                }

                // Always write a sync log entry
                Extole_Sync_Log__c logEntry = new Extole_Sync_Log__c();
                logEntry.Report_Name__c     = config.Report_Name__c;
                logEntry.Date_Range__c      = dateRange;
                logEntry.Executor_Type__c   = config.Executor_Type__c;
                logEntry.Status__c          = statusStr;
                logEntry.Sync_Timestamp__c  = System.now();
                logEntry.Value_Extracted__c = extractedVal;
                logEntry.HTTP_Status_Code__c = httpStatus;
                logEntry.Poll_Attempts__c   = pollAttempts;
                logEntry.Error_Message__c   = errMsg.length() > 255 ? errMsg.left(255) : errMsg;
                logEntry.Sync_Batch_Id__c   = batchId;
                syncLogs.add(logEntry);
            }
        }

        // ── Upsert snapshots (query-then-set-Id pattern) ─────────────────────
        if (!snapshotsToUpsert.isEmpty()) {
            // Load existing snapshots keyed by configId+dateRange to set Id for upsert
            Map<String, Id> existingSnapIds = new Map<String, Id>();
            for (Extole_Report_Snapshot__c existing : [
                SELECT Id, Config_Id__c, Date_Range__c
                FROM Extole_Report_Snapshot__c
                WHERE Config_Id__c IN :activeConfigIds
            ]) {
                existingSnapIds.put(existing.Config_Id__c + '|' + existing.Date_Range__c, existing.Id);
            }

            for (Extole_Report_Snapshot__c snap : snapshotsToUpsert) {
                String key = snap.Config_Id__c + '|' + snap.Date_Range__c;
                if (existingSnapIds.containsKey(key)) {
                    snap.Id = existingSnapIds.get(key);
                }
            }

            upsert snapshotsToUpsert;
            System.debug('ExtoleSyncJob: upserted ' + snapshotsToUpsert.size() + ' snapshots');

            if (debugEnabled) {
                debugLogs.add(makeDebugLog(
                    'BATCH', 'UPSERT_COMPLETE',
                    'Upserted ' + snapshotsToUpsert.size() + ' snapshot records', batchId
                ));
            }
        }

        // ── Orphan reconciliation ─────────────────────────────────────────────
        // SOQL NOT IN with an empty set returns no rows; add a sentinel value
        // that can never be a real Salesforce ID to ensure the NOT IN clause
        // still evaluates correctly when there are no active configs.
        Set<String> orphanCheckSet = new Set<String>(activeConfigIds);
        orphanCheckSet.add('000000000000000000'); // 18-char impossible sentinel
        List<Extole_Report_Snapshot__c> toMarkOrphaned = [
            SELECT Id, Config_Status__c
            FROM Extole_Report_Snapshot__c
            WHERE Config_Id__c NOT IN :orphanCheckSet
              AND Config_Status__c != 'ORPHANED'
        ];
        if (!toMarkOrphaned.isEmpty()) {
            for (Extole_Report_Snapshot__c s : toMarkOrphaned) {
                s.Config_Status__c = 'ORPHANED';
            }
            update toMarkOrphaned;
            System.debug('ExtoleSyncJob: marked ' + toMarkOrphaned.size() + ' snapshots as ORPHANED');
        }

        // ── Bulk insert sync logs ─────────────────────────────────────────────
        if (!syncLogs.isEmpty()) {
            insert syncLogs;
        }

        // ── Bulk insert debug logs ────────────────────────────────────────────
        if (!debugLogs.isEmpty()) {
            insert debugLogs;
        }

        // ── Update Last_Sync_Timestamp ────────────────────────────────────────
        settings.Last_Sync_Timestamp__c = System.now();
        upsert settings;
        System.debug('ExtoleSyncJob: updated Last_Sync_Timestamp to ' + settings.Last_Sync_Timestamp__c);

        // ── Failure notification ─────────────────────────────────────────────
        if (consecutiveFailCount > 0) {
            Integer prevConsecutive = (settings.Consecutive_Failure_Count__c != null)
                ? (Integer) settings.Consecutive_Failure_Count__c : 0;
            Integer newConsecutive  = prevConsecutive + 1;
            settings.Consecutive_Failure_Count__c = newConsecutive;
            upsert settings;

            Integer notifyAfter = (settings.Notify_After_N_Failures__c != null)
                ? (Integer) settings.Notify_After_N_Failures__c : 2;
            Boolean notifyEnabled = settings.Notify_On_Sync_Failure__c == true;

            if (notifyEnabled && newConsecutive >= notifyAfter
                && String.isNotBlank(settings.Failure_Notification_Email__c)) {
                sendFailureEmail(settings, lastError, batchId);
            }
        } else {
            // Reset consecutive failure count on success
            settings.Consecutive_Failure_Count__c = 0;
            upsert settings;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Prior-period helper
    // ─────────────────────────────────────────────────────────────────────────

    private static String runPriorPeriod(
        Extole_Report_Config__c config,
        String dateRange,
        String batchId,
        Boolean debugEnabled,
        List<Extole_Debug_Log__c> debugLogs,
        Http http
    ) {
        try {
            String priorParam = toPriorPeriodParam(dateRange);
            Map<String, Object> postBody = new Map<String, Object>{
                'name'   => config.Report_Name__c,
                'format' => 'JSON',
                'parameters' => new Map<String, Object>{
                    'date_range' => priorParam
                }
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Extole_API/v4/reports');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(postBody));
            req.setTimeout(30000);

            HttpResponse res = http.send(req);
            if (res.getStatusCode() != 200 && res.getStatusCode() != 201 && res.getStatusCode() != 202) {
                return null;
            }

            Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String priorReportId = (String) resp.get('report_id');

            // Poll
            Integer maxRetries = maxRetriesFor(config.Executor_Type__c);
            String  pollStatus = (String) resp.get('status');
            Integer attempts   = 0;

            while (attempts < maxRetries && pollStatus != 'DONE' && pollStatus != 'FAILED') {
                attempts++;
                HttpRequest pr = new HttpRequest();
                pr.setEndpoint('callout:Extole_API/v4/reports/' + priorReportId);
                pr.setMethod('GET');
                pr.setTimeout(15000);
                HttpResponse pRes = http.send(pr);
                Map<String, Object> pResp = (Map<String, Object>) JSON.deserializeUntyped(pRes.getBody());
                pollStatus = (String) pResp.get('status');
            }

            if (pollStatus != 'DONE') {
                return null;
            }

            // Download
            HttpRequest dlReq = new HttpRequest();
            dlReq.setEndpoint('callout:Extole_API/v4/reports/' + priorReportId + '/download');
            dlReq.setMethod('GET');
            dlReq.setTimeout(30000);
            HttpResponse dlRes = http.send(dlReq);

            if (debugEnabled) {
                debugLogs.add(makeDebugLog(
                    config.Report_Name__c, 'PRIOR_PERIOD_RAW',
                    'priorReportId=' + priorReportId + ' | ' + dlRes.getBody(), batchId
                ));
            }

            return extractValue(dlRes.getBody(), config.Value_Column__c, config.Aggregation__c);

        } catch (Exception e) {
            System.debug('ExtoleSyncJob.runPriorPeriod ERROR: ' + e.getMessage());
            return null;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Value extraction
    // ─────────────────────────────────────────────────────────────────────────

    public static String extractValue(String rawJson, String valueColumn, String aggregation) {
        if (String.isBlank(rawJson) || String.isBlank(valueColumn)) {
            return null;
        }

        List<Object> rows;
        try {
            rows = (List<Object>) JSON.deserializeUntyped(rawJson);
        } catch (Exception e) {
            System.debug('ExtoleSyncJob.extractValue: could not parse JSON: ' + e.getMessage());
            return null;
        }

        if (rows == null || rows.isEmpty()) {
            System.debug('ExtoleSyncJob.extractValue: empty result set');
            return null;
        }

        // Log all columns present for mismatch diagnostics
        Map<String, Object> firstRow = (Map<String, Object>) rows[0];
        System.debug('ExtoleSyncJob.extractValue: looking for column="' + valueColumn
            + '" | columns present=' + firstRow.keySet());

        if (aggregation == 'COUNT') {
            return String.valueOf(rows.size());
        }

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
                        System.debug('ExtoleSyncJob.extractValue SUM: could not parse value=' + val);
                    }
                }
            }
            return String.valueOf(total);
        }

        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Time series builder
    // ─────────────────────────────────────────────────────────────────────────

    private static String buildTimeSeriesJson(String rawJson, String valueColumn) {
        if (String.isBlank(rawJson) || String.isBlank(valueColumn)) {
            return null;
        }
        try {
            List<Object> rows = (List<Object>) JSON.deserializeUntyped(rawJson);
            List<Map<String, Object>> series = new List<Map<String, Object>>();
            for (Object rowObj : rows) {
                Map<String, Object> row = (Map<String, Object>) rowObj;
                Object val = row.get(valueColumn);
                // Look for a date/week column to use as the x-axis label
                String label = null;
                for (String key : row.keySet()) {
                    String keyLower = key.toLowerCase();
                    if (keyLower.contains('week') || keyLower.contains('date') || keyLower.contains('period')) {
                        label = String.valueOf(row.get(key));
                        break;
                    }
                }
                if (label == null) {
                    label = String.valueOf(series.size() + 1);
                }
                series.add(new Map<String, Object>{
                    'label' => label,
                    'value' => val != null ? String.valueOf(val) : '0'
                });
            }
            return JSON.serialize(series);
        } catch (Exception e) {
            System.debug('ExtoleSyncJob.buildTimeSeriesJson ERROR: ' + e.getMessage());
            return null;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utility: date range parameter mapping
    // ─────────────────────────────────────────────────────────────────────────

    public static String toDateRangeParam(String dateRange) {
        if (dateRange == 'Rolling 30')  return 'ROLLING_30_DAYS';
        if (dateRange == 'Rolling 90')  return 'ROLLING_90_DAYS';
        if (dateRange == 'YTD')         return 'YEAR_TO_DATE';
        return dateRange; // pass through if already a raw value
    }

    private static String toPriorPeriodParam(String dateRange) {
        if (dateRange == 'Rolling 30')  return 'PRIOR_30_DAYS';
        if (dateRange == 'Rolling 90')  return 'PRIOR_90_DAYS';
        if (dateRange == 'YTD')         return 'PRIOR_YEAR_TO_DATE';
        return 'PRIOR_' + dateRange;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utility: polling retry limits by executor type
    // ─────────────────────────────────────────────────────────────────────────

    public static Integer maxRetriesFor(String executorType) {
        if (executorType == 'SQL')         return 10;
        if (executorType == 'CONFIGURED')  return 20;
        if (executorType == 'SPARK')       return 40;
        return 20; // default
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utility: next expected sync calculation
    // ─────────────────────────────────────────────────────────────────────────

    private static DateTime calcNextExpectedSync(String cadence) {
        DateTime now = System.now();
        if (cadence == 'Every 6hrs')   return now.addHours(6);
        if (cadence == 'Every 12hrs')  return now.addHours(12);
        return now.addHours(24); // Nightly default
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utility: debug log factory
    // ─────────────────────────────────────────────────────────────────────────

    private static Extole_Debug_Log__c makeDebugLog(
        String reportName, String eventType, String detail, String batchId
    ) {
        Extole_Debug_Log__c log = new Extole_Debug_Log__c();
        log.Report_Name__c    = reportName;
        log.Log_Timestamp__c  = System.now();
        log.Event_Type__c     = eventType;
        log.Detail__c         = detail != null && detail.length() > 131072
                                    ? detail.left(131072)
                                    : detail;
        log.Sync_Batch_Id__c  = batchId;
        return log;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Failure notification email
    // ─────────────────────────────────────────────────────────────────────────

    private static void sendFailureEmail(
        Extole_App_Settings__c settings,
        String lastError,
        String batchId
    ) {
        try {
            String orgName    = UserInfo.getOrganizationName();
            String lastSuccess = settings.Last_Sync_Timestamp__c != null
                ? String.valueOf(settings.Last_Sync_Timestamp__c) : 'Never';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[]{ settings.Failure_Notification_Email__c });
            mail.setSubject('[Extole for Salesforce] Sync failure — action required');
            mail.setPlainTextBody(
                'Org: ' + orgName + '\n' +
                'Last successful sync: ' + lastSuccess + '\n' +
                'Error: ' + lastError + '\n' +
                'Batch ID: ' + batchId + '\n\n' +
                'Please review the sync log in the Extole App Settings tab for details.'
            );
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
            System.debug('ExtoleSyncJob: failure notification email sent to '
                + settings.Failure_Notification_Email__c);
        } catch (Exception e) {
            System.debug('ExtoleSyncJob.sendFailureEmail ERROR: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Custom exception
    // ─────────────────────────────────────────────────────────────────────────

    public class ExtoleSyncException extends Exception {}
}
