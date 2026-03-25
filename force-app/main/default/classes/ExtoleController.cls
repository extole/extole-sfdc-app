public with sharing class ExtoleController {

    // ─────────────────────────────────────────────────────────────────────────
    // Snapshots
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Extole_Report_Snapshot__c> getSnapshots() {
        return [
            SELECT Id, Name, Value__c, Prior_Period_Value__c, Time_Series_JSON__c,
                   Report_Name__c, Executor_Type__c, As_Of_Date__c, Date_Range__c,
                   Display_Order__c, Chart_Type__c, Next_Expected_Sync__c,
                   Config_Id__c, View_URL__c, Report_Id__c, Client_Id__c,
                   Config_Status__c, Display_Label__c
            FROM Extole_Report_Snapshot__c
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Configs
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Extole_Report_Config__c> getConfigs() {
        return [
            SELECT Id, Name, Report_Name__c, Report_Type__c, Executor_Type__c,
                   Display_Label__c, Value_Column__c, Aggregation__c, Chart_Type__c,
                   Data_Mode__c, Date_Range__c, Display_Order__c,
                   Parameter_Overrides_JSON__c, Active__c
            FROM Extole_Report_Config__c
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ];
    }

    @AuraEnabled
    public static Id saveConfig(Extole_Report_Config__c config) {
        System.debug('ExtoleController.saveConfig called for: ' + config.Report_Name__c);
        upsert config;
        return config.Id;
    }

    @AuraEnabled
    public static void deleteConfig(Id configId) {
        System.debug('ExtoleController.deleteConfig called for Id: ' + configId);
        delete new Extole_Report_Config__c(Id = configId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Sync Logs
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Extole_Sync_Log__c> getSyncLogs() {
        return [
            SELECT Id, Name, Report_Name__c, Date_Range__c, Executor_Type__c,
                   Status__c, Sync_Timestamp__c, Value_Extracted__c,
                   HTTP_Status_Code__c, Poll_Attempts__c, Error_Message__c,
                   Sync_Batch_Id__c
            FROM Extole_Sync_Log__c
            ORDER BY Sync_Timestamp__c DESC
            LIMIT 200
        ];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // App Settings
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static Extole_App_Settings__c getSettings() {
        // Return null for a brand-new org so the LWC onboarding flow triggers correctly.
        // The LWC checks for null to detect first-launch state.
        Extole_App_Settings__c s = Extole_App_Settings__c.getOrgDefaults();
        return s; // null when no settings record has been saved yet
    }

    @AuraEnabled
    public static void saveSettings(Extole_App_Settings__c settings) {
        System.debug('ExtoleController.saveSettings called');
        upsert settings;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Report Types (live callout)
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static String getReportTypes() {
        System.debug('ExtoleController.getReportTypes: calling Extole API');
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'callout:Extole_API/v6/report-types?limit=100&visibility=PUBLIC' +
            '&exclude_tags=internal:flag:archived,internal:flag:ending,internal:category:Legacy'
        );
        req.setMethod('GET');
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);
        System.debug('ExtoleController.getReportTypes: HTTP ' + res.getStatusCode());

        if (res.getStatusCode() != 200) {
            throw new AuraHandledException(
                'Extole API returned HTTP ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }
        return res.getBody();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Connection test
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> testConnection() {
        System.debug('ExtoleController.testConnection: pinging Extole API');
        Map<String, Object> result = new Map<String, Object>{
            'success' => false,
            'reportCount' => 0,
            'errorMessage' => ''
        };

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Extole_API/v6/report-types?limit=5');
            req.setMethod('GET');
            req.setTimeout(15000);

            Http http = new Http();
            HttpResponse res = http.send(req);
            System.debug('ExtoleController.testConnection: HTTP ' + res.getStatusCode());

            if (res.getStatusCode() == 200) {
                List<Object> reportTypes = (List<Object>) JSON.deserializeUntyped(res.getBody());
                result.put('success', true);
                result.put('reportCount', reportTypes.size());
            } else {
                result.put('errorMessage',
                    'HTTP ' + res.getStatusCode() + ': ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug('ExtoleController.testConnection ERROR: ' + e.getMessage());
            result.put('errorMessage', e.getMessage());
        }
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Sync triggers
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled
    public static void triggerSync() {
        System.debug('ExtoleController.triggerSync: starting full sync');
        // Enqueue a one-shot future/queueable so we return quickly to the LWC
        ExtoleSyncJob.runNow();
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> triggerSingleSync(Id configId) {
        System.debug('ExtoleController.triggerSingleSync: configId=' + configId);

        Extole_Report_Config__c config = [
            SELECT Id, Name, Report_Name__c, Report_Type__c, Executor_Type__c,
                   Display_Label__c, Value_Column__c, Aggregation__c, Chart_Type__c,
                   Data_Mode__c, Date_Range__c, Display_Order__c,
                   Parameter_Overrides_JSON__c, Active__c
            FROM Extole_Report_Config__c
            WHERE Id = :configId
            LIMIT 1
        ];

        String batchId = String.valueOf(System.currentTimeMillis())
                       + '-' + UserInfo.getUserId().left(8);

        Map<String, Object> result = new Map<String, Object>{
            'value' => null,
            'rawOutput' => '',
            'status' => 'FAILED'
        };

        try {
            // POST to trigger report execution
            String dateRangeParam = ExtoleSyncJob.toDateRangeParam(config.Date_Range__c);
            Map<String, Object> postBody = new Map<String, Object>{
                'name'   => config.Report_Name__c,
                'format' => 'JSON',
                'parameters' => new Map<String, Object>{
                    'date_range' => dateRangeParam
                }
            };

            HttpRequest postReq = new HttpRequest();
            postReq.setEndpoint('callout:Extole_API/v4/reports');
            postReq.setMethod('POST');
            postReq.setHeader('Content-Type', 'application/json');
            postReq.setBody(JSON.serialize(postBody));
            postReq.setTimeout(30000);

            Http http = new Http();
            HttpResponse postRes = http.send(postReq);
            System.debug('triggerSingleSync POST HTTP ' + postRes.getStatusCode());

            if (postRes.getStatusCode() != 200 && postRes.getStatusCode() != 201 && postRes.getStatusCode() != 202) {
                result.put('status', 'FAILED');
                result.put('rawOutput', 'POST failed: HTTP ' + postRes.getStatusCode() + ' ' + postRes.getBody());
                return result;
            }

            Map<String, Object> postResp = (Map<String, Object>) JSON.deserializeUntyped(postRes.getBody());
            String reportId = (String) postResp.get('report_id');

            // Poll for completion
            Integer maxRetries = ExtoleSyncJob.maxRetriesFor(config.Executor_Type__c);
            Integer attempts   = 0;
            String  status     = 'PROCESSING';

            while (attempts < maxRetries && status != 'DONE' && status != 'FAILED') {
                attempts++;
                HttpRequest pollReq = new HttpRequest();
                pollReq.setEndpoint('callout:Extole_API/v4/reports/' + reportId);
                pollReq.setMethod('GET');
                pollReq.setTimeout(15000);
                HttpResponse pollRes = http.send(pollReq);
                Map<String, Object> pollResp = (Map<String, Object>) JSON.deserializeUntyped(pollRes.getBody());
                status = (String) pollResp.get('status');
                System.debug('triggerSingleSync poll attempt=' + attempts + ' status=' + status);
            }

            if (status != 'DONE') {
                result.put('status', 'FAILED');
                result.put('rawOutput', 'Report did not complete. Last status: ' + status);
                return result;
            }

            // Download
            HttpRequest dlReq = new HttpRequest();
            dlReq.setEndpoint('callout:Extole_API/v4/reports/' + reportId + '/download');
            dlReq.setMethod('GET');
            dlReq.setTimeout(30000);
            HttpResponse dlRes = http.send(dlReq);
            String rawJson = dlRes.getBody();
            result.put('rawOutput', rawJson);

            // Extract value
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
            result.put('status', 'FAILED');
            result.put('rawOutput', e.getMessage());
        }

        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Maintenance
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled
    public static Integer clearOrphanedSnapshots() {
        System.debug('ExtoleController.clearOrphanedSnapshots: querying orphaned snapshots');
        List<Extole_Report_Snapshot__c> orphans = [
            SELECT Id
            FROM Extole_Report_Snapshot__c
            WHERE Config_Status__c = 'ORPHANED'
        ];
        if (!orphans.isEmpty()) {
            delete orphans;
        }
        System.debug('ExtoleController.clearOrphanedSnapshots: deleted ' + orphans.size());
        return orphans.size();
    }

    @AuraEnabled
    public static Integer clearDebugLogs() {
        System.debug('ExtoleController.clearDebugLogs: deleting all debug logs');
        List<Extole_Debug_Log__c> logs = [SELECT Id FROM Extole_Debug_Log__c LIMIT 10000];
        if (!logs.isEmpty()) {
            delete logs;
        }
        System.debug('ExtoleController.clearDebugLogs: deleted ' + logs.size());
        return logs.size();
    }
}
