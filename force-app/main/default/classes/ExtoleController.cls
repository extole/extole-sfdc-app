public with sharing class ExtoleController {

    // ─────────────────────────────────────────────────────────────────────────
    // Snapshots
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<Extole_Report_Snapshot__c> getSnapshots() {
        return [
            SELECT Id, Name, Value__c, Prior_Period_Value__c, Time_Series_JSON__c,
                   Report_Name__c, Executor_Type__c, As_Of_Date__c, Date_Range__c,
                   Display_Order__c, Chart_Type__c, Next_Expected_Sync__c,
                   Config_Id__c, View_URL__c, Report_Id__c, Client_Id__c,
                   Config_Status__c, Display_Label__c, Schedule_URL__c
            FROM Extole_Report_Snapshot__c
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Configs
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<Extole_Report_Config__c> getConfigs() {
        return [
            SELECT Id, Name, CreatedDate, LastModifiedDate, Report_Name__c, Report_Type__c, Executor_Type__c,
                   Display_Label__c, Value_Column__c, Aggregation__c, Chart_Type__c,
                   Data_Mode__c, Date_Range__c, Display_Order__c,
                   Parameter_Overrides_JSON__c, Active__c, Comparison_Period__c
            FROM Extole_Report_Config__c
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ];
    }

    @AuraEnabled
    public static Id saveConfig(Extole_Report_Config__c config) {
        System.debug('ExtoleController.saveConfig called for: ' + config.Report_Name__c);
        upsert config;

        // Immediately push display-only fields to the matching snapshot so the
        // dashboard reflects config changes without waiting for the next sync.
        List<Extole_Report_Snapshot__c> snaps = [
            SELECT Id FROM Extole_Report_Snapshot__c
            WHERE Config_Id__c = :config.Id
            LIMIT 1
        ];
        if (!snaps.isEmpty()) {
            Extole_Report_Snapshot__c snap = snaps[0];
            snap.Chart_Type__c    = config.Chart_Type__c;
            snap.Display_Label__c = config.Display_Label__c;
            snap.Display_Order__c = config.Display_Order__c;
            snap.Name             = config.Display_Label__c != null
                                        ? config.Display_Label__c : config.Report_Name__c;
            update snap;
        }

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

    @AuraEnabled(cacheable=false)
    public static List<Extole_Sync_Log__c> getSyncLogs() {
        return [
            SELECT Id, Name, Report_Name__c, Date_Range__c, Executor_Type__c,
                   Status__c, Trigger_Type__c, Sync_Timestamp__c, Value_Extracted__c,
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

        // Wire up the scheduled job before saving so the job ID lands in the same upsert.
        // Wrapped in try-catch so a scheduling failure never prevents settings from saving.
        try {
            String jobId = ExtoleSyncJob.scheduleJob(settings.Sync_Cadence__c);
            settings.Scheduled_Job_Id__c = jobId;
        } catch (Exception e) {
            System.debug('ExtoleController.saveSettings: scheduleJob failed (non-fatal): ' + e.getMessage());
        }

        upsert settings;

        // Refresh Next_Expected_Sync__c on all active snapshots immediately so the
        // tile stale indicator reflects the new cadence without waiting for next sync.
        if (settings.Sync_Cadence__c != null) {
            DateTime nextExpected = ExtoleSyncJob.calcNextExpectedSync(settings.Sync_Cadence__c);
            List<Extole_Report_Snapshot__c> snaps = [
                SELECT Id FROM Extole_Report_Snapshot__c WHERE Config_Status__c = 'ACTIVE'
            ];
            for (Extole_Report_Snapshot__c snap : snaps) {
                snap.Next_Expected_Sync__c = nextExpected;
            }
            if (!snaps.isEmpty()) update snaps;
        }
    }

    @AuraEnabled
    public static void clearSyncLogs() {
        try {
            List<Extole_Sync_Log__c> logs = [SELECT Id FROM Extole_Sync_Log__c LIMIT 10000];
            if (!logs.isEmpty()) delete logs;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to clear sync log: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getScheduleStatus() {
        Map<String, Object> result = new Map<String, Object>{
            'isScheduled' => false,
            'cadence'     => ''
        };
        Extole_App_Settings__c s = Extole_App_Settings__c.getOrgDefaults();
        if (s == null) return result;

        result.put('cadence', s.Sync_Cadence__c != null ? s.Sync_Cadence__c : '');

        List<CronTrigger> jobs = [
            SELECT Id, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'ExtoleSync_%'
              AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
            LIMIT 1
        ];
        result.put('isScheduled', !jobs.isEmpty());
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Report Types (live callout)
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static String getReportTypes() {
        System.debug('ExtoleController.getReportTypes: calling Extole API /v7/report-runners');
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Extole_API/v7/report-runners?type=SCHEDULED');
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
            req.setEndpoint('callout:Extole_API/v7/report-runners?type=SCHEDULED');
            req.setMethod('GET');
            req.setTimeout(15000);

            Http http = new Http();
            HttpResponse res = http.send(req);
            System.debug('ExtoleController.testConnection: HTTP ' + res.getStatusCode());

            if (res.getStatusCode() == 200) {
                List<Object> runners = (List<Object>) JSON.deserializeUntyped(res.getBody());
                result.put('success', true);
                result.put('reportCount', runners.size());
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
    public static Integer triggerSync() {
        System.debug('ExtoleController.triggerSync: starting full sync');
        return ExtoleSyncJob.runNow();
    }

    @AuraEnabled(cacheable=false)
    public static List<String> getReportColumns(String runnerId) {
        System.debug('ExtoleController.getReportColumns: runnerId=' + runnerId);
        Http http = new Http();

        // Step 1: find a completed report — try /latest first, fall back to /reports list
        String reportId = null;

        HttpRequest latestReq = new HttpRequest();
        latestReq.setEndpoint('callout:Extole_API/v6/report-runners/' + runnerId + '/latest');
        latestReq.setMethod('GET');
        latestReq.setTimeout(30000);
        HttpResponse latestRes = http.send(latestReq);

        if (latestRes.getStatusCode() == 200) {
            Map<String, Object> latestResp = (Map<String, Object>) JSON.deserializeUntyped(latestRes.getBody());
            String status = (String) latestResp.get('status');
            if (status == 'DONE') {
                reportId = latestResp.get('report_id') != null
                    ? (String) latestResp.get('report_id')
                    : (String) latestResp.get('id');
            }
        }

        // If latest isn't DONE, search recent reports for a completed one
        if (String.isBlank(reportId)) {
            HttpRequest histReq = new HttpRequest();
            histReq.setEndpoint('callout:Extole_API/v6/report-runners/' + runnerId + '/reports?limit=10');
            histReq.setMethod('GET');
            histReq.setTimeout(30000);
            HttpResponse histRes = http.send(histReq);

            if (histRes.getStatusCode() == 200) {
                List<Object> reports = (List<Object>) JSON.deserializeUntyped(histRes.getBody());
                for (Object r : reports) {
                    Map<String, Object> rpt = (Map<String, Object>) r;
                    if (rpt.get('status') == 'DONE') {
                        reportId = rpt.get('report_id') != null
                            ? (String) rpt.get('report_id')
                            : (String) rpt.get('id');
                        break;
                    }
                }
            }
        }

        if (String.isBlank(reportId)) {
            throw new AuraHandledException('No completed report found for this runner yet. Try again after the next scheduled run.');
        }

        // Step 2: download and extract column names from first row
        HttpRequest dlReq = new HttpRequest();
        dlReq.setEndpoint('callout:Extole_API/v4/reports/' + reportId + '/download.json');
        dlReq.setMethod('GET');
        dlReq.setTimeout(30000);
        HttpResponse dlRes = http.send(dlReq);

        if (dlRes.getStatusCode() != 200) {
            throw new AuraHandledException('Could not download report: HTTP ' + dlRes.getStatusCode());
        }

        List<Object> rows = (List<Object>) JSON.deserializeUntyped(dlRes.getBody());
        if (rows == null || rows.isEmpty()) {
            return new List<String>();
        }

        List<String> columns = new List<String>(((Map<String, Object>) rows[0]).keySet());
        columns.sort();
        return columns;
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> triggerSingleSync(Id configId) {
        System.debug('ExtoleController.triggerSingleSync: configId=' + configId);

        Extole_Report_Config__c config = [
            SELECT Id, Name, Report_Name__c, Report_Type__c, Executor_Type__c,
                   Display_Label__c, Value_Column__c, Aggregation__c, Chart_Type__c,
                   Data_Mode__c, Date_Range__c, Display_Order__c,
                   Parameter_Overrides_JSON__c, Active__c, Comparison_Period__c
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

            // GET latest report for this runner
            HttpRequest latestReq = new HttpRequest();
            latestReq.setEndpoint('callout:Extole_API/v6/report-runners/' + runnerId + '/latest');
            latestReq.setMethod('GET');
            latestReq.setTimeout(30000);

            HttpResponse latestRes = http.send(latestReq);
            System.debug('triggerSingleSync /latest HTTP ' + latestRes.getStatusCode());

            if (latestRes.getStatusCode() != 200) {
                result.put('rawOutput', 'GET /latest failed: HTTP ' + latestRes.getStatusCode() + ' ' + latestRes.getBody());
                return result;
            }

            Map<String, Object> latestResp = (Map<String, Object>) JSON.deserializeUntyped(latestRes.getBody());
            String reportId = latestResp.get('report_id') != null
                ? (String) latestResp.get('report_id')
                : latestResp.get('id') != null ? (String) latestResp.get('id') : null;

            if (String.isBlank(reportId)) {
                result.put('rawOutput', 'No report_id in /latest response: ' + latestRes.getBody());
                return result;
            }

            // Download
            HttpRequest dlReq = new HttpRequest();
            dlReq.setEndpoint('callout:Extole_API/v4/reports/' + reportId + '/download.json');
            dlReq.setMethod('GET');
            dlReq.setTimeout(30000);
            HttpResponse dlRes = http.send(dlReq);
            String rawJson = dlRes.getBody();
            result.put('rawOutput', rawJson);

            if (dlRes.getStatusCode() != 200) {
                result.put('rawOutput', 'Download failed HTTP ' + dlRes.getStatusCode() + ': ' + rawJson);
                return result;
            }

            String extractedValue = ExtoleSyncJob.extractValue(
                rawJson, config.Value_Column__c, config.Aggregation__c
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

    // ─────────────────────────────────────────────────────────────────────────
    // Maintenance
    // ─────────────────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────────────────
    // Lead Attribution
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<Map<String, String>> getObjectFields(String objectName) {
        List<Map<String, String>> fields = new List<Map<String, String>>();

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
        if (objType == null) return fields;

        Set<Schema.DisplayType> allowedTypes = new Set<Schema.DisplayType>{
            Schema.DisplayType.STRING,
            Schema.DisplayType.PICKLIST,
            Schema.DisplayType.MULTIPICKLIST,
            Schema.DisplayType.EMAIL,
            Schema.DisplayType.PHONE,
            Schema.DisplayType.TEXTAREA,
            Schema.DisplayType.URL,
            Schema.DisplayType.CURRENCY,
            Schema.DisplayType.DOUBLE,
            Schema.DisplayType.INTEGER,
            Schema.DisplayType.PERCENT,
            Schema.DisplayType.DATE,
            Schema.DisplayType.DATETIME
        };

        // Special virtual field for Contact's and Opportunity's related Account name
        if (objectName == 'Contact' || objectName == 'Opportunity') {
            fields.add(new Map<String, String>{ 'label' => 'Account Name', 'value' => 'Account.Name' });
        }

        for (Schema.SObjectField f : objType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult fd = f.getDescribe();
            if (!allowedTypes.contains(fd.getType())) continue;
            if (!fd.isAccessible()) continue;
            fields.add(new Map<String, String>{
                'label' => fd.getLabel(),
                'value' => fd.getName()
            });
        }
        return fields;
    }

    @AuraEnabled(cacheable=false)
    public static List<String> getFieldValues(String objectName, String fieldName) {
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
        if (objType == null) return new List<String>();

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey(fieldName.toLowerCase())) return new List<String>();

        Schema.DescribeFieldResult fd = fieldMap.get(fieldName.toLowerCase()).getDescribe();

        // Picklist: return defined entries
        if (fd.getType() == Schema.DisplayType.PICKLIST
                || fd.getType() == Schema.DisplayType.MULTIPICKLIST) {
            List<String> vals = new List<String>();
            for (Schema.PicklistEntry e : fd.getPicklistValues()) {
                if (e.isActive()) vals.add(e.getValue());
            }
            return vals;
        }

        // Text / other: return distinct values from existing records
        String soql = 'SELECT ' + fieldName
                    + ' FROM ' + objectName
                    + ' WHERE ' + fieldName + ' != null'
                    + ' GROUP BY ' + fieldName
                    + ' LIMIT 100';
        List<AggregateResult> rows = Database.query(soql);
        List<String> vals = new List<String>();
        for (AggregateResult r : rows) {
            Object v = r.get(fieldName);
            if (v != null) vals.add(String.valueOf(v));
        }
        return vals;
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getAttributedLeads() {
        Map<String, Object> result = new Map<String, Object>{
            'records'    => new List<Object>(),
            'configured' => false,
            'totalCount' => 0,
            'objectType' => 'Contact',
            'field'      => '',
            'value'      => '',
            'startDate'  => null
        };

        Extole_App_Settings__c s = Extole_App_Settings__c.getOrgDefaults();
        if (s == null
                || String.isBlank(s.List_View_Field__c)
                || String.isBlank(s.List_View_Value__c)) {
            return result;
        }

        String objectType = String.isBlank(s.List_View_Object__c)
                            ? 'Contact' : s.List_View_Object__c;
        String fieldName  = s.List_View_Field__c.trim();
        String fieldValue = s.List_View_Value__c;
        Date   startDate  = s.List_View_Start_Date__c;

        // Validate field exists on target object
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectType);
        if (objType == null || !objType.getDescribe().fields.getMap().containsKey(fieldName.toLowerCase())) {
            result.put('error', 'Field "' + fieldName + '" does not exist on ' + objectType + '. Check Lead Attribution settings.');
            return result;
        }

        // Resolve extra display columns (saved setting or smart defaults)
        String columnsRaw = String.isBlank(s.List_View_Columns__c)
            ? (objectType == 'Contact' ? 'Account.Name,Email,Title' : 'Email,Company,Status')
            : s.List_View_Columns__c;

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        List<Map<String, String>> extraColumns = new List<Map<String, String>>();
        List<String> extraSelect = new List<String>();

        for (String col : columnsRaw.split(',')) {
            col = col.trim();
            if (String.isBlank(col) || col.equalsIgnoreCase(fieldName)) continue;

            if (col == 'Account.Name' && (objectType == 'Contact' || objectType == 'Opportunity')) {
                extraSelect.add('Account.Name');
                extraColumns.add(new Map<String, String>{
                    'label'     => 'Account Name',
                    'fieldName' => 'Account.Name',
                    'flatKey'   => 'Account__Name'
                });
            } else if (fieldMap.containsKey(col.toLowerCase())) {
                Schema.DescribeFieldResult efd = fieldMap.get(col.toLowerCase()).getDescribe();
                if (!efd.isAccessible()) continue;
                extraSelect.add(col);
                extraColumns.add(new Map<String, String>{
                    'label'     => efd.getLabel(),
                    'fieldName' => col,
                    'flatKey'   => col
                });
            }
        }

        String selectClause = 'Id, Name, ' + fieldName + ', CreatedDate, Owner.Name';
        if (!extraSelect.isEmpty()) {
            selectClause += ', ' + String.join(extraSelect, ', ');
        }

        String soql = 'SELECT ' + selectClause
                    + ' FROM '  + objectType
                    + ' WHERE ' + fieldName + ' = :fieldValue';
        if (startDate != null) {
            soql += ' AND CreatedDate >= :startDate';
        }
        soql += ' ORDER BY CreatedDate DESC LIMIT 500';

        List<SObject> records = Database.query(soql);

        // Accurate counts via COUNT() — not capped by the 500-record LIMIT
        String baseWhere = fieldName + ' = :fieldValue'
            + (startDate != null ? ' AND CreatedDate >= :startDate' : '');
        Integer totalCnt = Database.countQuery(
            'SELECT COUNT() FROM ' + objectType + ' WHERE ' + baseWhere);

        Date firstOfMonth = Date.today().toStartOfMonth();
        Integer thisMonthCnt = Database.countQuery(
            'SELECT COUNT() FROM ' + objectType + ' WHERE ' + baseWhere
            + ' AND CreatedDate >= :firstOfMonth');

        Integer monthIdx = Date.today().month() - 1;
        Date firstOfQuarter = Date.newInstance(
            Date.today().year(), monthIdx - Math.mod(monthIdx, 3) + 1, 1);
        Integer thisQuarterCnt = Database.countQuery(
            'SELECT COUNT() FROM ' + objectType + ' WHERE ' + baseWhere
            + ' AND CreatedDate >= :firstOfQuarter');

        result.put('records',         records);
        result.put('configured',      true);
        result.put('totalCount',      totalCnt);
        result.put('thisMonthCount',  thisMonthCnt);
        result.put('thisQuarterCount',thisQuarterCnt);
        result.put('objectType',      objectType);
        result.put('field',           fieldName);
        result.put('value',           fieldValue);
        result.put('startDate',       startDate);
        result.put('extraColumns',    extraColumns);
        return result;
    }

@AuraEnabled(cacheable=false)
    public static List<Extole_Debug_Log__c> getDebugLogs() {
        return [
            SELECT Id, Name, Report_Name__c, Event_Type__c, Detail__c,
                   Log_Timestamp__c, Sync_Batch_Id__c
            FROM Extole_Debug_Log__c
            ORDER BY Log_Timestamp__c DESC
            LIMIT 200
        ];
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
