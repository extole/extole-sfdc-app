public with sharing class ExtoleController {
    @AuraEnabled(cacheable=true)
    public static String getCurrentUserTimezone() {
        return UserInfo.getTimeZone().getID();
    }

    @AuraEnabled(cacheable=false)
    public static List<Extole_Report_Snapshot__c> getSnapshots() {
        return [
            SELECT
                Id,
                Name,
                Value__c,
                Prior_Period_Value__c,
                Time_Series_JSON__c,
                Report_Name__c,
                Executor_Type__c,
                As_Of_Date__c,
                Date_Range__c,
                Display_Order__c,
                Chart_Type__c,
                Next_Expected_Sync__c,
                Config_Id__c,
                View_URL__c,
                Report_Id__c,
                Client_Id__c,
                Config_Status__c,
                Display_Label__c,
                Schedule_URL__c
            FROM Extole_Report_Snapshot__c
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ];
    }

    @AuraEnabled(cacheable=false)
    public static List<Extole_Report_Config__c> getConfigs() {
        return [
            SELECT
                Id,
                Name,
                CreatedDate,
                LastModifiedDate,
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
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ];
    }

    @AuraEnabled
    public static Id saveConfig(Extole_Report_Config__c config) {
        System.debug(
            'ExtoleController.saveConfig called for: ' + config.Report_Name__c
        );
        upsert config;

        List<Extole_Report_Snapshot__c> snapshots = [
            SELECT Id
            FROM Extole_Report_Snapshot__c
            WHERE Config_Id__c = :config.Id
            LIMIT 1
        ];
        if (!snapshots.isEmpty()) {
            Extole_Report_Snapshot__c snapshot = snapshots[0];
            snapshot.Chart_Type__c = config.Chart_Type__c;
            snapshot.Display_Label__c = config.Display_Label__c;
            snapshot.Display_Order__c = config.Display_Order__c;
            snapshot.Name = config.Display_Label__c != null
                ? config.Display_Label__c
                : config.Report_Name__c;
            update snapshot;
        }

        return config.Id;
    }

    @AuraEnabled
    public static void deleteConfig(Id configId) {
        System.debug(
            'ExtoleController.deleteConfig called for Id: ' + configId
        );
        delete new Extole_Report_Config__c(Id = configId);
    }

    @AuraEnabled(cacheable=false)
    public static List<Extole_Sync_Log__c> getSyncLogs() {
        return [
            SELECT
                Id,
                Name,
                Report_Name__c,
                Date_Range__c,
                Executor_Type__c,
                Status__c,
                Trigger_Type__c,
                Sync_Timestamp__c,
                Value_Extracted__c,
                HTTP_Status_Code__c,
                Poll_Attempts__c,
                Error_Message__c,
                Sync_Batch_Id__c
            FROM Extole_Sync_Log__c
            ORDER BY Sync_Timestamp__c DESC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=false)
    public static Extole_App_Settings__c getSettings() {
        try {
            ExtoleLogPurgeJob.ensureScheduled();
        } catch (Exception e) {
            System.debug(
                'ExtoleController.getSettings: could not ensure log purge job scheduled — ' +
                e.getMessage()
            );
        }

        Extole_App_Settings__c s = Extole_App_Settings__c.getOrgDefaults();
        return s;
    }

    @AuraEnabled
    public static void saveSettings(Extole_App_Settings__c settings) {
        System.debug('ExtoleController.saveSettings called');

        try {
            String jobId = ExtoleSyncJob.scheduleJob(settings.Sync_Cadence__c);
            settings.Scheduled_Job_Id__c = jobId;
        } catch (Exception e) {
            System.debug(
                'ExtoleController.saveSettings: scheduleJob failed (non-fatal): ' +
                e.getMessage()
            );
        }

        upsert settings;

        if (settings.Sync_Cadence__c != null) {
            DateTime nextExpected = ExtoleSyncJob.calcNextExpectedSync(
                settings.Sync_Cadence__c
            );
            List<Extole_Report_Snapshot__c> snapshots = [
                SELECT Id
                FROM Extole_Report_Snapshot__c
                WHERE Config_Status__c = 'ACTIVE'
            ];
            for (Extole_Report_Snapshot__c snapshot : snapshots) {
                snapshot.Next_Expected_Sync__c = nextExpected;
            }
            if (!snapshots.isEmpty())
                update snapshots;
        }
    }

    @AuraEnabled
    public static void clearSyncLogs() {
        try {
            List<Extole_Sync_Log__c> logs = [
                SELECT Id
                FROM Extole_Sync_Log__c
                LIMIT 10000
            ];
            if (!logs.isEmpty())
                delete logs;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to clear sync log: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getScheduleStatus() {
        Map<String, Object> result = new Map<String, Object>{
            'isScheduled' => false,
            'cadence' => ''
        };
        Extole_App_Settings__c s = Extole_App_Settings__c.getOrgDefaults();
        if (s == null)
            return result;

        result.put(
            'cadence',
            s.Sync_Cadence__c != null ? s.Sync_Cadence__c : ''
        );

        List<CronTrigger> jobs = [
            SELECT Id, State
            FROM CronTrigger
            WHERE
                CronJobDetail.Name LIKE 'ExtoleSync_%'
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
            LIMIT 1
        ];
        result.put('isScheduled', !jobs.isEmpty());
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static String getReportTypes() {
        System.debug(
            'ExtoleController.getReportTypes: calling Extole API /v7/report-runners'
        );
        HttpRequest request = new HttpRequest();
        request.setEndpoint(
            'callout:Extole_API/v7/report-runners?type=SCHEDULED'
        );
        request.setMethod('GET');
        request.setTimeout(30000);

        Http http = new Http();
        HttpResponse response = http.send(request);
        System.debug(
            'ExtoleController.getReportTypes: HTTP ' + response.getStatusCode()
        );

        if (response.getStatusCode() != 200) {
            throw new AuraHandledException(
                'Extole API returned HTTP ' +
                    response.getStatusCode() +
                    ': ' +
                    response.getBody()
            );
        }
        return response.getBody();
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> testConnection() {
        System.debug('ExtoleController.testConnection: pinging Extole API');
        Map<String, Object> result = new Map<String, Object>{
            'success' => false,
            'reportCount' => 0,
            'errorMessage' => ''
        };

        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(
                'callout:Extole_API/v7/report-runners?type=SCHEDULED'
            );
            request.setMethod('GET');
            request.setTimeout(15000);

            Http http = new Http();
            HttpResponse response = http.send(request);
            System.debug(
                'ExtoleController.testConnection: HTTP ' +
                response.getStatusCode()
            );

            if (response.getStatusCode() == 200) {
                List<Object> runners = (List<Object>) JSON.deserializeUntyped(
                    response.getBody()
                );
                result.put('success', true);
                result.put('reportCount', runners.size());
            } else {
                result.put(
                    'errorMessage',
                    'HTTP ' +
                        response.getStatusCode() +
                        ': ' +
                        response.getBody()
                );
            }
        } catch (Exception e) {
            System.debug(
                'ExtoleController.testConnection ERROR: ' + e.getMessage()
            );
            result.put('errorMessage', e.getMessage());
        }
        return result;
    }

    @AuraEnabled
    public static Integer triggerSync() {
        System.debug('ExtoleController.triggerSync: starting full sync');
        return ExtoleSyncJob.runNow();
    }

    @AuraEnabled(cacheable=false)
    public static List<String> getReportColumns(String runnerId) {
        System.debug('ExtoleController.getReportColumns: runnerId=' + runnerId);
        Http http = new Http();

        String reportId = null;

        HttpRequest latestRequest = new HttpRequest();
        latestRequest.setEndpoint(
            'callout:Extole_API/v6/report-runners/' + runnerId + '/latest'
        );
        latestRequest.setMethod('GET');
        latestRequest.setTimeout(30000);
        HttpResponse latestHttpResponse = http.send(latestRequest);

        if (latestHttpResponse.getStatusCode() == 200) {
            Map<String, Object> latestResponseData = (Map<String, Object>) JSON.deserializeUntyped(
                latestHttpResponse.getBody()
            );
            String status = (String) latestResponseData.get('status');
            if (status == 'DONE') {
                reportId = latestResponseData.get('report_id') != null
                    ? (String) latestResponseData.get('report_id')
                    : (String) latestResponseData.get('id');
            }
        }

        if (String.isBlank(reportId)) {
            HttpRequest historyRequest = new HttpRequest();
            historyRequest.setEndpoint(
                'callout:Extole_API/v6/report-runners/' +
                    runnerId +
                    '/reports?limit=10'
            );
            historyRequest.setMethod('GET');
            historyRequest.setTimeout(30000);
            HttpResponse historyHttpResponse = http.send(historyRequest);

            if (historyHttpResponse.getStatusCode() == 200) {
                List<Object> reports = (List<Object>) JSON.deserializeUntyped(
                    historyHttpResponse.getBody()
                );
                for (Object r : reports) {
                    Map<String, Object> report = (Map<String, Object>) r;
                    if (report.get('status') == 'DONE') {
                        reportId = report.get('report_id') != null
                            ? (String) report.get('report_id')
                            : (String) report.get('id');
                        break;
                    }
                }
            }
        }

        if (String.isBlank(reportId)) {
            throw new AuraHandledException(
                'No completed report found for this runner yet. Try again after the next scheduled run.'
            );
        }

        HttpRequest downloadRequest = new HttpRequest();
        downloadRequest.setEndpoint(
            'callout:Extole_API/v4/reports/' + reportId + '/download.json'
        );
        downloadRequest.setMethod('GET');
        downloadRequest.setTimeout(30000);
        HttpResponse downloadHttpResponse = http.send(downloadRequest);

        if (downloadHttpResponse.getStatusCode() != 200) {
            throw new AuraHandledException(
                'Could not download report: HTTP ' +
                downloadHttpResponse.getStatusCode()
            );
        }

        List<Object> rows = (List<Object>) JSON.deserializeUntyped(
            downloadHttpResponse.getBody()
        );
        if (rows == null || rows.isEmpty()) {
            return new List<String>();
        }

        List<String> columns = new List<String>(
            ((Map<String, Object>) rows[0]).keySet()
        );
        columns.sort();
        return columns;
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> triggerSingleSync(Id configId) {
        System.debug(
            'ExtoleController.triggerSingleSync: configId=' + configId
        );

        Extole_Report_Config__c config = [
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
            WHERE Id = :configId
            LIMIT 1
        ];

        Map<String, Object> result = new Map<String, Object>{
            'value' => null,
            'rawOutput' => '',
            'status' => 'FAILED'
        };

        try {
            String runnerId = config.Report_Type__c;
            Http http = new Http();

            HttpRequest latestRequest = new HttpRequest();
            latestRequest.setEndpoint(
                'callout:Extole_API/v6/report-runners/' + runnerId + '/latest'
            );
            latestRequest.setMethod('GET');
            latestRequest.setTimeout(30000);

            HttpResponse latestHttpResponse = http.send(latestRequest);
            System.debug(
                'triggerSingleSync /latest HTTP ' +
                latestHttpResponse.getStatusCode()
            );

            if (latestHttpResponse.getStatusCode() != 200) {
                result.put(
                    'rawOutput',
                    'GET /latest failed: HTTP ' +
                        latestHttpResponse.getStatusCode() +
                        ' ' +
                        latestHttpResponse.getBody()
                );
                return result;
            }

            Map<String, Object> latestResponseData = (Map<String, Object>) JSON.deserializeUntyped(
                latestHttpResponse.getBody()
            );
            String reportId = latestResponseData.get('report_id') != null
                ? (String) latestResponseData.get('report_id')
                : latestResponseData.get('id') != null
                      ? (String) latestResponseData.get('id')
                      : null;

            if (String.isBlank(reportId)) {
                result.put(
                    'rawOutput',
                    'No report_id in /latest response: ' +
                    latestHttpResponse.getBody()
                );
                return result;
            }

            HttpRequest downloadRequest = new HttpRequest();
            downloadRequest.setEndpoint(
                'callout:Extole_API/v4/reports/' + reportId + '/download.json'
            );
            downloadRequest.setMethod('GET');
            downloadRequest.setTimeout(30000);
            HttpResponse downloadHttpResponse = http.send(downloadRequest);
            String rawJson = downloadHttpResponse.getBody();
            result.put('rawOutput', rawJson);

            if (downloadHttpResponse.getStatusCode() != 200) {
                result.put(
                    'rawOutput',
                    'Download failed HTTP ' +
                        downloadHttpResponse.getStatusCode() +
                        ': ' +
                        rawJson
                );
                return result;
            }

            String extractedValue = ExtoleSyncJob.extractValue(
                rawJson,
                config.Value_Column__c,
                config.Aggregation__c
            );
            result.put('value', extractedValue);
            result.put('status', 'SUCCESS');
            System.debug('triggerSingleSync extracted value=' + extractedValue);
        } catch (Exception e) {
            System.debug('triggerSingleSync ERROR: ' + e.getMessage());
            result.put('rawOutput', e.getMessage());
        }

        return result;
    }

    @AuraEnabled(cacheable=false)
    public static List<Extole_Debug_Log__c> getDebugLogs() {
        return [
            SELECT
                Id,
                Name,
                Report_Name__c,
                Event_Type__c,
                Detail__c,
                Log_Timestamp__c,
                Sync_Batch_Id__c
            FROM Extole_Debug_Log__c
            ORDER BY Log_Timestamp__c DESC
            LIMIT 200
        ];
    }

    @AuraEnabled
    public static Integer clearDebugLogs() {
        System.debug(
            'ExtoleController.clearDebugLogs: deleting all debug logs'
        );
        List<Extole_Debug_Log__c> logs = [
            SELECT Id
            FROM Extole_Debug_Log__c
            LIMIT 10000
        ];
        if (!logs.isEmpty()) {
            delete logs;
        }
        System.debug('ExtoleController.clearDebugLogs: deleted ' + logs.size());
        return logs.size();
    }
}
