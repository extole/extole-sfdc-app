public class ExtoleSyncJob implements Schedulable {
    public void execute(SchedulableContext context) {
        System.debug('ExtoleSyncJob.execute: scheduled run triggered');
        System.enqueueJob(new SyncQueueable());
    }

    public class SyncQueueable implements Queueable, Database.AllowsCallouts {
        public void execute(QueueableContext context) {
            ExtoleSyncJob.performSync('Scheduled');
        }
    }

    public static Integer runNow() {
        System.debug('ExtoleSyncJob.runNow: manual sync triggered');
        return performSync('Manual');
    }

    @TestVisible
    private static Integer performSync(String triggerType) {
        String batchId =
            String.valueOf(System.currentTimeMillis()) +
            '-' +
            UserInfo.getUserId().left(8);
        System.debug('ExtoleSyncJob.performSync: batchId=' + batchId);

        Extole_App_Settings__c settings = Extole_App_Settings__c.getOrgDefaults();
        if (settings == null)
            settings = new Extole_App_Settings__c();
        Boolean debugEnabled = settings.Debug_Logging_Enabled__c == true;
        Integer historyDepth = settings.History_Depth__c != null
            ? (Integer) settings.History_Depth__c
            : 30;

        List<Extole_Report_Config__c> configs = [
            SELECT
                Id,
                Name,
                Report_Name__c,
                Report_Type__c,
                Executor_Type__c,
                Display_Label__c,
                Value_Column__c,
                Aggregation__c,
                Chart_Type__c,
                Data_Mode__c,
                Date_Range__c,
                Display_Order__c,
                Parameter_Overrides_JSON__c,
                Active__c,
                Comparison_Period__c
            FROM Extole_Report_Config__c
            WHERE Active__c = TRUE
        ];
        System.debug(
            'ExtoleSyncJob: found ' + configs.size() + ' active configs'
        );

        if (configs.isEmpty()) {
            List<Extole_Report_Snapshot__c> allSnapshots = [
                SELECT Id
                FROM Extole_Report_Snapshot__c
            ];
            if (!allSnapshots.isEmpty())
                delete allSnapshots;
            writeSyncFields(settings.Id, System.now(), null);
            return 0;
        }

        Map<String, List<Extole_Report_Config__c>> configsByRunner = new Map<String, List<Extole_Report_Config__c>>();
        Set<String> activeConfigIds = new Set<String>();

        for (Extole_Report_Config__c config : configs) {
            activeConfigIds.add(config.Id);
            String rid = config.Report_Type__c;
            if (!configsByRunner.containsKey(rid)) {
                configsByRunner.put(rid, new List<Extole_Report_Config__c>());
            }
            configsByRunner.get(rid).add(config);
        }

        Map<String, Extole_Report_Snapshot__c> existingByConfigId = new Map<String, Extole_Report_Snapshot__c>();
        for (Extole_Report_Snapshot__c snapshot : [
            SELECT
                Id,
                Config_Id__c,
                As_Of_Date__c,
                Time_Series_JSON__c,
                Report_Id__c,
                Value__c,
                View_URL__c,
                Client_Id__c
            FROM Extole_Report_Snapshot__c
            WHERE Config_Id__c IN :activeConfigIds
        ]) {
            existingByConfigId.put(snapshot.Config_Id__c, snapshot);
        }

        Map<String, List<Map<String, Object>>> seriesByConfigId = new Map<String, List<Map<String, Object>>>();
        Map<String, Long> lastDateMsByConfigId = new Map<String, Long>();

        for (String configId : activeConfigIds) {
            Extole_Report_Snapshot__c snapshot = existingByConfigId.get(
                configId
            );
            List<Map<String, Object>> series = snapshot != null
                ? parseTimeSeries(snapshot.Time_Series_JSON__c)
                : new List<Map<String, Object>>();
            seriesByConfigId.put(configId, series);
            lastDateMsByConfigId.put(configId, getLastSeriesDateMs(series));
        }

        Integer numRunners = configsByRunner.size();
        Integer downloadBudget = 90 - numRunners;
        Integer effectiveDepth = Math.max(
            1,
            Math.min(historyDepth, downloadBudget / numRunners)
        );
        System.debug(
            'ExtoleSyncJob: numRunners=' +
                numRunners +
                ' effectiveDepth=' +
                effectiveDepth
        );

        Map<String, List<Map<String, Object>>> runnerDownloads = new Map<String, List<Map<String, Object>>>();

        List<Extole_Sync_Log__c> syncLogs = new List<Extole_Sync_Log__c>();
        List<Extole_Debug_Log__c> debugLogs = new List<Extole_Debug_Log__c>();
        Integer consecutiveFailCount = 0;
        String lastError = '';
        Set<String> failedRunnerIds = new Set<String>();

        Http http = new Http();

        for (String runnerId : configsByRunner.keySet()) {
            List<Extole_Report_Config__c> runnerConfigs = configsByRunner.get(
                runnerId
            );

            Long runnerCutoffMs = 9999999999999L;
            for (Extole_Report_Config__c config : runnerConfigs) {
                Long d = lastDateMsByConfigId.get(config.Id);
                if (d == null || d < 0L) {
                    runnerCutoffMs = -1L;
                    break;
                }
                if (d < runnerCutoffMs)
                    runnerCutoffMs = d;
            }

            List<Map<String, Object>> completedReports = new List<Map<String, Object>>();
            String listError = '';
            Integer listHttpStatus = 0;

            try {
                String listUrl =
                    'callout:Extole_API/v6/report-runners/' +
                    runnerId +
                    '/reports?limit=' +
                    effectiveDepth;
                HttpRequest listRequest = new HttpRequest();
                listRequest.setEndpoint(listUrl);
                listRequest.setMethod('GET');
                listRequest.setTimeout(30000);
                HttpResponse listResponse = http.send(listRequest);
                listHttpStatus = listResponse.getStatusCode();

                System.debug(
                    'ExtoleSyncJob /reports HTTP ' +
                        listResponse.getStatusCode() +
                        ' runner=' +
                        runnerId
                );

                if (debugEnabled) {
                    debugLogs.add(
                        makeDebugLog(
                            runnerId,
                            'HTTP_RESPONSE',
                            'GET /reports | HTTP ' +
                                listResponse.getStatusCode() +
                                ' | ' +
                                listResponse.getBody().left(500),
                            batchId
                        )
                    );
                }

                if (listResponse.getStatusCode() != 200) {
                    listError =
                        'List reports HTTP ' +
                        listResponse.getStatusCode() +
                        ': ' +
                        listResponse.getBody().left(200);
                } else {
                    List<Object> raw = (List<Object>) JSON.deserializeUntyped(
                        listResponse.getBody()
                    );
                    List<Map<String, Object>> doneReports = new List<Map<String, Object>>();
                    for (Object r : raw) {
                        Map<String, Object> report = (Map<String, Object>) r;
                        if (report.get('status') == 'DONE')
                            doneReports.add(report);
                    }
                    for (Integer i = doneReports.size() - 1; i >= 0; i--) {
                        completedReports.add(doneReports[i]);
                    }
                }
            } catch (Exception e) {
                listError = e.getMessage();
                System.debug(
                    'ExtoleSyncJob: list reports failed for runner ' +
                        runnerId +
                        ': ' +
                        listError
                );
            }

            if (!String.isBlank(listError)) {
                for (Extole_Report_Config__c config : runnerConfigs) {
                    consecutiveFailCount++;
                    lastError = listError;
                    Extole_Sync_Log__c logEntry = new Extole_Sync_Log__c();
                    logEntry.Report_Name__c = config.Report_Name__c;
                    logEntry.Status__c = 'FAILED';
                    logEntry.Trigger_Type__c = triggerType;
                    logEntry.Sync_Timestamp__c = System.now();
                    logEntry.HTTP_Status_Code__c = listHttpStatus > 0
                        ? listHttpStatus
                        : null;
                    logEntry.Error_Message__c = listError.left(255);
                    logEntry.Sync_Batch_Id__c = batchId;
                    syncLogs.add(logEntry);
                }
                if (listHttpStatus == 404) {
                    Set<String> configIds = new Set<String>();
                    for (Extole_Report_Config__c config : runnerConfigs)
                        configIds.add(config.Id);
                    List<Extole_Report_Snapshot__c> unavailableSnapshots = [
                        SELECT Id, Config_Status__c
                        FROM Extole_Report_Snapshot__c
                        WHERE Config_Id__c IN :configIds
                    ];
                    if (!unavailableSnapshots.isEmpty()) {
                        for (
                            Extole_Report_Snapshot__c s : unavailableSnapshots
                        ) {
                            s.Config_Status__c = 'SOURCE_UNAVAILABLE';
                        }
                        update unavailableSnapshots;
                    }
                }
                failedRunnerIds.add(runnerId);
                runnerDownloads.put(runnerId, new List<Map<String, Object>>());
                continue;
            }

            List<Map<String, Object>> downloaded = new List<Map<String, Object>>();

            for (Map<String, Object> report : completedReports) {
                String reportId = report.get('report_id') != null
                    ? (String) report.get('report_id')
                    : report.get('id') != null
                          ? (String) report.get('id')
                          : null;
                if (String.isBlank(reportId))
                    continue;

                String createdAt = report.get('created_at') != null
                    ? (String) report.get('created_at')
                    : '';
                Long createdAtMs = parseDateMs(createdAt);

                if (
                    runnerCutoffMs > 0 &&
                    createdAtMs > 0 &&
                    createdAtMs <= runnerCutoffMs
                ) {
                    continue;
                }

                String rawJson = null;
                try {
                    HttpRequest downloadRequest = new HttpRequest();
                    downloadRequest.setEndpoint(
                        'callout:Extole_API/v4/reports/' +
                            reportId +
                            '/download.json'
                    );
                    downloadRequest.setMethod('GET');
                    downloadRequest.setTimeout(30000);
                    HttpResponse downloadResponse = http.send(downloadRequest);

                    System.debug(
                        'ExtoleSyncJob download HTTP ' +
                            downloadResponse.getStatusCode() +
                            ' reportId=' +
                            reportId
                    );

                    if (debugEnabled) {
                        debugLogs.add(
                            makeDebugLog(
                                runnerId,
                                'HTTP_RESPONSE',
                                'GET /download.json | reportId=' +
                                    reportId +
                                    ' | HTTP ' +
                                    downloadResponse.getStatusCode() +
                                    ' | len=' +
                                    downloadResponse.getBody().length(),
                                batchId
                            )
                        );
                    }

                    if (downloadResponse.getStatusCode() == 200)
                        rawJson = downloadResponse.getBody();
                } catch (Exception e) {
                    System.debug(
                        'ExtoleSyncJob: download failed for report ' +
                            reportId +
                            ': ' +
                            e.getMessage()
                    );
                }

                if (rawJson == null)
                    continue;

                downloaded.add(
                    new Map<String, Object>{
                        'reportId' => reportId,
                        'createdAt' => createdAt,
                        'createdAtMs' => createdAtMs,
                        'viewUrl' => report.get('view_url') != null
                            ? report.get('view_url')
                            : '',
                        'clientId' => report.get('client_id') != null
                            ? report.get('client_id')
                            : '',
                        'rawJson' => rawJson
                    }
                );
            }

            runnerDownloads.put(runnerId, downloaded);
            System.debug(
                'ExtoleSyncJob: runner=' +
                    runnerId +
                    ' downloaded=' +
                    downloaded.size() +
                    ' new reports'
            );
        }

        List<Extole_Report_Snapshot__c> snapshotsToUpsert = new List<Extole_Report_Snapshot__c>();

        for (Extole_Report_Config__c config : configs) {
            String runnerId = config.Report_Type__c;
            if (failedRunnerIds.contains(runnerId))
                continue;
            List<Map<String, Object>> downloads = runnerDownloads.get(runnerId);
            if (downloads == null)
                downloads = new List<Map<String, Object>>();

            List<Map<String, Object>> series = new List<Map<String, Object>>();
            series.addAll(seriesByConfigId.get(config.Id));
            Long configLastDateMs = lastDateMsByConfigId.get(config.Id);
            if (configLastDateMs == null)
                configLastDateMs = -1L;

            String latestExtractedValue = null;
            String latestReportId = null;
            String latestViewUrl = '';
            String latestClientId = '';
            Long latestReportDateMs = -1L;
            String statusStr = 'SUCCESS';
            String errMsg = '';

            try {
                for (Map<String, Object> dl : downloads) {
                    Long dlDateMs = (Long) dl.get('createdAtMs');

                    if (
                        dlDateMs != null &&
                        dlDateMs > 0 &&
                        configLastDateMs > 0 &&
                        dlDateMs <= configLastDateMs
                    ) {
                        continue;
                    }

                    String rawJson = (String) dl.get('rawJson');
                    String value = extractValue(
                        rawJson,
                        config.Value_Column__c,
                        config.Aggregation__c
                    );

                    String pointDate = (String) dl.get('createdAt');
                    if (String.isBlank(pointDate)) {
                        pointDate = System.now()
                            .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
                    }
                    series.add(
                        new Map<String, Object>{
                            'date' => pointDate,
                            'value' => value != null ? value : '0'
                        }
                    );

                    latestExtractedValue = value;
                    latestReportId = (String) dl.get('reportId');
                    latestViewUrl = (String) dl.get('viewUrl');
                    latestClientId = (String) dl.get('clientId');
                    latestReportDateMs = dlDateMs != null ? dlDateMs : -1L;
                }

                Extole_Report_Snapshot__c existing = existingByConfigId.get(
                    config.Id
                );
                if (latestExtractedValue == null && existing != null) {
                    latestExtractedValue = existing.Value__c;
                }

                if (series.size() > historyDepth) {
                    List<Map<String, Object>> trimmed = new List<Map<String, Object>>();
                    for (
                        Integer i = series.size() - historyDepth;
                        i < series.size();
                        i++
                    ) {
                        trimmed.add(series[i]);
                    }
                    series = trimmed;
                }

                String priorValue = null;
                Integer compDays = parseComparisonDays(
                    config.Comparison_Period__c
                );
                if (compDays > 0 && !series.isEmpty()) {
                    priorValue = findClosestSeriesValue(
                        series,
                        System.now().addDays(-compDays)
                    );
                    System.debug(
                        'ExtoleSyncJob: priorValue=' +
                            priorValue +
                            ' compDays=' +
                            compDays +
                            ' for ' +
                            config.Report_Name__c
                    );
                }

                Extole_Report_Snapshot__c snapshot = existing != null
                    ? existing
                    : new Extole_Report_Snapshot__c();

                snapshot.Name = config.Display_Label__c != null
                    ? config.Display_Label__c
                    : config.Report_Name__c;
                snapshot.Display_Label__c = config.Display_Label__c;
                snapshot.Value__c = latestExtractedValue;
                snapshot.Prior_Period_Value__c = priorValue;
                snapshot.Time_Series_JSON__c = series.isEmpty()
                    ? null
                    : JSON.serialize(series);
                snapshot.Report_Name__c = config.Report_Name__c;
                snapshot.Executor_Type__c = config.Executor_Type__c;
                snapshot.As_Of_Date__c = System.now();
                snapshot.Date_Range__c = config.Comparison_Period__c != null
                    ? config.Comparison_Period__c
                    : config.Date_Range__c;
                snapshot.Display_Order__c = config.Display_Order__c;
                snapshot.Chart_Type__c = config.Chart_Type__c;
                snapshot.Config_Id__c = config.Id;
                snapshot.Config_Status__c = 'ACTIVE';
                snapshot.Next_Expected_Sync__c = calcNextExpectedSync(
                    settings.Sync_Cadence__c
                );

                if (latestReportId != null) {
                    snapshot.View_URL__c = latestViewUrl;
                    snapshot.Report_Id__c = latestReportId;
                    snapshot.Client_Id__c = latestClientId;
                    snapshot.Schedule_URL__c =
                        'https://my.extole.com/reports?user_id=' +
                        latestClientId +
                        '#/schedules/' +
                        runnerId;
                }

                snapshotsToUpsert.add(snapshot);

                if (debugEnabled) {
                    String firstDate = !series.isEmpty()
                        ? (String) series[0].get('date')
                        : 'n/a';
                    String lastDate = series.size() > 1
                        ? (String) series[series.size() - 1].get('date')
                        : 'n/a';
                    debugLogs.add(
                        makeDebugLog(
                            config.Report_Name__c,
                            'VALUE_EXTRACTED',
                            'value=' +
                                latestExtractedValue +
                                ' priorValue=' +
                                priorValue +
                                ' seriesLen=' +
                                series.size() +
                                ' firstDate=' +
                                firstDate +
                                ' lastDate=' +
                                lastDate,
                            batchId
                        )
                    );
                }
            } catch (Exception e) {
                consecutiveFailCount++;
                errMsg = e.getMessage();
                lastError = errMsg;
                statusStr = 'FAILED';
                System.debug(
                    'ExtoleSyncJob ERROR for config ' +
                        config.Report_Name__c +
                        ': ' +
                        errMsg
                );
            }

            Extole_Sync_Log__c logEntry = new Extole_Sync_Log__c();
            logEntry.Report_Name__c = config.Report_Name__c;
            logEntry.Date_Range__c = String.isNotBlank(
                    config.Comparison_Period__c
                )
                ? config.Comparison_Period__c
                : config.Date_Range__c;
            logEntry.Executor_Type__c = config.Executor_Type__c;
            logEntry.Status__c = statusStr;
            logEntry.Trigger_Type__c = triggerType;
            logEntry.Sync_Timestamp__c = System.now();
            logEntry.Value_Extracted__c = latestExtractedValue;
            logEntry.HTTP_Status_Code__c = statusStr == 'SUCCESS' ? 200 : null;
            logEntry.Poll_Attempts__c = 0;
            logEntry.Error_Message__c = errMsg.length() > 255
                ? errMsg.left(255)
                : errMsg;
            logEntry.Sync_Batch_Id__c = batchId;
            syncLogs.add(logEntry);
        }

        if (!snapshotsToUpsert.isEmpty()) {
            upsert snapshotsToUpsert;
            System.debug(
                'ExtoleSyncJob: upserted ' +
                    snapshotsToUpsert.size() +
                    ' snapshots'
            );
        }

        Set<String> orphanCheckSet = new Set<String>(activeConfigIds);
        orphanCheckSet.add('000000000000000000');
        List<Extole_Report_Snapshot__c> toDelete = [
            SELECT Id
            FROM Extole_Report_Snapshot__c
            WHERE Config_Id__c NOT IN :orphanCheckSet
        ];
        if (!toDelete.isEmpty()) {
            delete toDelete;
            System.debug(
                'ExtoleSyncJob: deleted ' +
                    toDelete.size() +
                    ' orphaned snapshots'
            );
        }

        if (!syncLogs.isEmpty())
            insert syncLogs;
        if (!debugLogs.isEmpty())
            insert debugLogs;

        Integer prevConsecutive = settings.Consecutive_Failure_Count__c != null
            ? (Integer) settings.Consecutive_Failure_Count__c
            : 0;
        Integer newConsecutive = consecutiveFailCount > 0
            ? prevConsecutive + 1
            : 0;
        writeSyncFields(settings.Id, System.now(), newConsecutive);

        if (consecutiveFailCount > 0) {
            Integer notifyAfter = settings.Notify_After_N_Failures__c != null
                ? (Integer) settings.Notify_After_N_Failures__c
                : 2;
            Boolean notifyEnabled = settings.Notify_On_Sync_Failure__c == true;

            if (
                notifyEnabled &&
                newConsecutive >= notifyAfter &&
                String.isNotBlank(settings.Failure_Notification_Email__c)
            ) {
                sendFailureEmail(settings, lastError, batchId);
            }
        }

        return consecutiveFailCount;
    }

    public static String extractValue(
        String rawJson,
        String valueColumn,
        String aggregation
    ) {
        if (String.isBlank(rawJson))
            return null;

        List<Object> rows;
        try {
            rows = (List<Object>) JSON.deserializeUntyped(rawJson);
        } catch (Exception e) {
            System.debug(
                'ExtoleSyncJob.extractValue: could not parse JSON: ' +
                e.getMessage()
            );
            return null;
        }

        if (rows == null || rows.isEmpty())
            return null;

        if (aggregation == 'COUNT') {
            return String.valueOf(rows.size());
        }

        if (String.isBlank(valueColumn))
            return null;

        Map<String, Object> firstRow = (Map<String, Object>) rows[0];
        System.debug(
            'ExtoleSyncJob.extractValue: column="' +
                valueColumn +
                '" | columns=' +
                firstRow.keySet()
        );

        if (aggregation == 'FIRST_ROW') {
            Object value = firstRow.get(valueColumn);
            return value != null ? String.valueOf(value) : null;
        }

        if (aggregation == 'SUM') {
            Decimal total = 0;
            for (Object rowObj : rows) {
                Map<String, Object> row = (Map<String, Object>) rowObj;
                Object value = row.get(valueColumn);
                if (value != null) {
                    try {
                        total += Decimal.valueOf(String.valueOf(value));
                    } catch (Exception e) {
                        System.debug(
                            'ExtoleSyncJob.extractValue SUM: non-numeric value=' +
                            value
                        );
                    }
                }
            }
            return String.valueOf(total);
        }

        return null;
    }

    private static List<Map<String, Object>> parseTimeSeries(String jsonStr) {
        if (String.isBlank(jsonStr))
            return new List<Map<String, Object>>();
        try {
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(jsonStr);
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            for (Object o : raw)
                result.add((Map<String, Object>) o);
            return result;
        } catch (Exception e) {
            return new List<Map<String, Object>>();
        }
    }

    private static Long getLastSeriesDateMs(List<Map<String, Object>> series) {
        if (series == null || series.isEmpty())
            return -1L;
        Long maxMs = -1L;
        for (Map<String, Object> pt : series) {
            Long ms = parseDateMs((String) pt.get('date'));
            if (ms > maxMs)
                maxMs = ms;
        }
        return maxMs;
    }

    private static Long parseDateMs(String isoDate) {
        if (String.isBlank(isoDate))
            return -1L;
        try {
            String cleaned = isoDate.replace('T', ' ');
            if (cleaned.length() > 19)
                cleaned = cleaned.substring(0, 19);
            return DateTime.valueOfGmt(cleaned).getTime();
        } catch (Exception e) {
            return -1L;
        }
    }

    private static String findClosestSeriesValue(
        List<Map<String, Object>> series,
        DateTime targetDate
    ) {
        Long targetMs = targetDate.getTime();
        Long minDiff = null;
        String closest = null;

        for (Map<String, Object> pt : series) {
            Long ptMs = parseDateMs((String) pt.get('date'));
            if (ptMs < 0)
                continue;
            Long diff = Math.abs(targetMs - ptMs);
            if (minDiff == null || diff < minDiff) {
                minDiff = diff;
                closest = (String) pt.get('value');
            }
        }
        if (closest == null && !series.isEmpty()) {
            closest = (String) series[0].get('value');
        }
        return closest;
    }

    private static Integer parseComparisonDays(String period) {
        if ('1 day' == period)
            return 1;
        if ('7 days' == period)
            return 7;
        if ('14 days' == period)
            return 14;
        if ('30 days' == period)
            return 30;
        if ('90 days' == period)
            return 90;
        return 0;
    }

    public static DateTime calcNextExpectedSync(String cadence) {
        DateTime now = System.now();
        if (cadence == 'Every 30min')
            return now.addMinutes(30);
        if (cadence == 'Every 6hrs')
            return now.addHours(6);
        if (cadence == 'Every 12hrs')
            return now.addHours(12);
        return now.addHours(24);
    }

    private static Extole_Debug_Log__c makeDebugLog(
        String reportName,
        String eventType,
        String detail,
        String batchId
    ) {
        Extole_Debug_Log__c log = new Extole_Debug_Log__c();
        log.Report_Name__c = reportName;
        log.Log_Timestamp__c = System.now();
        log.Event_Type__c = eventType;
        log.Detail__c = detail != null &&
            detail.length() > 131072
            ? detail.left(131072)
            : detail;
        log.Sync_Batch_Id__c = batchId;
        return log;
    }

    private static void writeSyncFields(
        Id settingsId,
        DateTime lastSync,
        Integer failCount
    ) {
        Extole_App_Settings__c upd;
        if (settingsId != null) {
            List<Extole_App_Settings__c> rows = [
                SELECT
                    Id,
                    Last_Sync_Timestamp__c,
                    Consecutive_Failure_Count__c,
                    Notify_On_Sync_Failure__c,
                    Notify_After_N_Failures__c,
                    Failure_Notification_Email__c,
                    Sync_Cadence__c,
                    Debug_Logging_Enabled__c,
                    History_Depth__c,
                    Scheduled_Job_Id__c
                FROM Extole_App_Settings__c
                WHERE Id = :settingsId
                LIMIT 1
            ];
            upd = rows.isEmpty() ? new Extole_App_Settings__c() : rows[0];
        } else {
            upd = new Extole_App_Settings__c();
        }
        upd.Last_Sync_Timestamp__c = lastSync;
        upd.Consecutive_Failure_Count__c = failCount;
        upsert upd;
    }

    private static void sendFailureEmail(
        Extole_App_Settings__c settings,
        String lastError,
        String batchId
    ) {
        try {
            String orgName = UserInfo.getOrganizationName();
            String lastSuccess = settings.Last_Sync_Timestamp__c != null
                ? String.valueOf(settings.Last_Sync_Timestamp__c)
                : 'Never';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(
                new List<String>{ settings.Failure_Notification_Email__c }
            );
            mail.setSaveAsActivity(false);
            mail.setSubject(
                '[Extole for Salesforce] Sync failure — action required'
            );
            mail.setPlainTextBody(
                'Org: ' +
                    orgName +
                    '\n' +
                    'Last successful sync: ' +
                    lastSuccess +
                    '\n' +
                    'Error: ' +
                    lastError +
                    '\n' +
                    'Batch ID: ' +
                    batchId +
                    '\n\n' +
                    'Please review the sync log in the Extole App Settings tab for details.'
            );
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            System.debug(
                'ExtoleSyncJob.sendFailureEmail: sent to ' +
                settings.Failure_Notification_Email__c
            );

            insert new Extole_Debug_Log__c(
                Report_Name__c = 'SYSTEM',
                Log_Timestamp__c = System.now(),
                Event_Type__c = 'EMAIL_SENT',
                Detail__c = 'Failure notification sent to: ' +
                    settings.Failure_Notification_Email__c +
                    ' | Error: ' +
                    lastError.left(200),
                Sync_Batch_Id__c = batchId
            );
        } catch (Exception e) {
            System.debug(
                'ExtoleSyncJob.sendFailureEmail ERROR: ' + e.getMessage()
            );
            insert new Extole_Debug_Log__c(
                Report_Name__c = 'SYSTEM',
                Log_Timestamp__c = System.now(),
                Event_Type__c = 'EMAIL_ERROR',
                Detail__c = 'Failed to send notification to: ' +
                    settings.Failure_Notification_Email__c +
                    ' | Exception: ' +
                    e.getMessage(),
                Sync_Batch_Id__c = batchId
            );
        }
    }

    public static String scheduleJob(String cadence) {
        List<CronTrigger> existingJobs = [
            SELECT Id
            FROM CronTrigger
            WHERE
                CronJobDetail.Name LIKE 'ExtoleSync_%'
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
        ];
        for (CronTrigger job : existingJobs) {
            try {
                System.abortJob(job.Id);
                System.debug(
                    'ExtoleSyncJob.scheduleJob: aborted job ' + job.Id
                );
            } catch (Exception e) {
                System.debug(
                    'ExtoleSyncJob.scheduleJob: could not abort job ' +
                        job.Id +
                        ': ' +
                        e.getMessage()
                );
            }
        }

        if (String.isBlank(cadence) || cadence == 'None') {
            System.debug(
                'ExtoleSyncJob.scheduleJob: cadence=None, no job scheduled'
            );
            return null;
        }

        String ts = String.valueOf(System.currentTimeMillis());

        if (cadence == 'Every 30min') {
            String id1 = System.schedule(
                'ExtoleSync_30m_top_' + ts,
                '0 0 * * * ?',
                new ExtoleSyncJob()
            );
            String id2 = System.schedule(
                'ExtoleSync_30m_bot_' + ts,
                '0 30 * * * ?',
                new ExtoleSyncJob()
            );
            System.debug(
                'ExtoleSyncJob.scheduleJob: scheduled Every 30min id1=' +
                    id1 +
                    ' id2=' +
                    id2
            );
            return id1;
        }

        String cronExpression;
        if (cadence == 'Every 6hrs')
            cronExpression = '0 0 0/6 * * ?';
        else if (cadence == 'Every 12hrs')
            cronExpression = '0 0 0/12 * * ?';
        else
            cronExpression = '0 0 2 * * ?';

        String jobName = 'ExtoleSync_' + ts;
        String jobId = System.schedule(
            jobName,
            cronExpression,
            new ExtoleSyncJob()
        );
        System.debug(
            'ExtoleSyncJob.scheduleJob: scheduled id=' +
                jobId +
                ' cadence=' +
                cadence
        );
        return jobId;
    }

    public class ExtoleSyncException extends Exception {
    }
}
