public with sharing class ExtoleBackfillController {

    // ─────────────────────────────────────────────────────────────────────────
    // Field discovery
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static String getShareLinkFieldSetting(String objectType) {
        Extole_App_Settings__c s = Extole_App_Settings__c.getOrgDefaults();
        String saved = objectType == 'Lead' ? s.Lead_Share_Link_Field__c : s.Contact_Share_Link_Field__c;
        String candidate = String.isNotBlank(saved) ? saved : 'Extole_Share_Link__c';
        return fieldExists(objectType, candidate) ? candidate : null;
    }

    private static Boolean fieldExists(String objectType, String fieldName) {
        if (String.isBlank(objectType) || String.isBlank(fieldName)) return false;
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectType);
        if (sot == null) return false;
        return sot.getDescribe().fields.getMap().containsKey(fieldName.toLowerCase());
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, String>> getWritebackFields(String objectType) {
        List<Map<String, String>> fields = new List<Map<String, String>>();
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectType);
        if (sot == null) return fields;

        Set<Schema.DisplayType> allowed = new Set<Schema.DisplayType>{
            Schema.DisplayType.STRING,
            Schema.DisplayType.URL
        };

        for (Schema.SObjectField f : sot.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult fd = f.getDescribe();
            if (!allowed.contains(fd.getType())) continue;
            if (!fd.isAccessible() || !fd.isUpdateable()) continue;
            if (!fd.isCustom()) continue; // only custom fields — standard fields shouldn't store share links
            fields.add(new Map<String, String>{
                'label' => fd.getLabel() + ' (' + fd.getName() + ')',
                'value' => fd.getName()
            });
        }

        fields.sort(new FieldLabelComparator());
        return fields;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Campaign discovery (for program label picker)
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<Map<String, String>> getExtoleCampaigns() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Extole_API/v2/campaign-summaries');
            req.setMethod('GET');
            req.setTimeout(10000);
            req.setHeader('Accept', 'application/json');
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) return options;

            Object parsed = JSON.deserializeUntyped(res.getBody());
            List<Object> campaigns = new List<Object>();
            if (parsed instanceof List<Object>) {
                campaigns = (List<Object>) parsed;
            } else if (parsed instanceof Map<String, Object>) {
                Object raw = ((Map<String, Object>) parsed).get('campaigns');
                if (raw instanceof List<Object>) campaigns = (List<Object>) raw;
            }

            // Group by program_label — one dropdown entry per program, exclude hidden
            Map<String, String> seenLabels = new Map<String, String>();
            for (Object c : campaigns) {
                if (!(c instanceof Map<String, Object>)) continue;
                Map<String, Object> campaign = (Map<String, Object>) c;
                String programLabel = (String) campaign.get('program_label');
                String name         = (String) campaign.get('name');
                List<Object> tags   = campaign.get('tags') instanceof List<Object> ? (List<Object>) campaign.get('tags') : new List<Object>();
                if (String.isBlank(programLabel)) continue;
                if (tags.contains('hidden')) continue;
                if (!seenLabels.containsKey(programLabel)) {
                    seenLabels.put(programLabel, String.isNotBlank(name) ? name : programLabel);
                }
            }
            for (String programLabel : seenLabels.keySet()) {
                options.add(new Map<String, String>{
                    'label' => seenLabels.get(programLabel),
                    'value' => programLabel
                });
            }
            options.sort(new FieldLabelComparator());
        } catch (Exception e) {
            System.debug('ExtoleBackfillController.getExtoleCampaigns: ' + e.getMessage());
        }
        return options;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Report discovery
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<Map<String, String>> getReports(String searchTerm) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        try {
            String q = 'SELECT Id, Name FROM Report';
            if (String.isNotBlank(searchTerm)) {
                q += ' WHERE Name LIKE \'%' + String.escapeSingleQuotes(searchTerm) + '%\'';
            }
            q += ' ORDER BY Name LIMIT 200';
            for (Report r : Database.query(q)) {
                options.add(new Map<String, String>{ 'label' => r.Name, 'value' => r.Id });
            }
        } catch (Exception e) {
            System.debug('ExtoleBackfillController.getReports: ' + e.getMessage());
        }
        return options;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Audience preview count
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static Integer previewCount(String objectType, String audienceType, String selectedDate, String reportId) {
        if (audienceType == 'report' && String.isNotBlank(reportId)) {
            return countFromReport(reportId);
        }
        if (audienceType == 'date' && String.isNotBlank(selectedDate)) {
            return countFromDateFilter(objectType, selectedDate);
        }
        return countFromDefaultFilter(objectType);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Start backfill
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static Id startBackfill(String objectType, String audienceType, String selectedDate, String reportId, String targetField, String programLabel, String programName) {
        persistShareLinkFieldSetting(objectType, targetField);

        String audienceTypeLabel;
        String audienceCriteria;
        if (audienceType == 'report') {
            audienceTypeLabel = 'Report';
            audienceCriteria  = reportId;
        } else if (audienceType == 'date') {
            audienceTypeLabel = 'Date Filter';
            audienceCriteria  = 'Created on or after ' + selectedDate;
        } else {
            audienceTypeLabel = 'Default Filter';
            audienceCriteria  = defaultFilterDescription(objectType);
        }

        Extole_Backfill_Log__c log = new Extole_Backfill_Log__c(
            Object_Type__c       = objectType,
            Audience_Type__c     = audienceTypeLabel,
            Audience_Criteria__c = audienceCriteria,
            Target_Field__c      = targetField,
            Program_Label__c     = String.isNotBlank(programName) ? programName : programLabel,
            Status__c            = 'IN_PROGRESS',
            Started_At__c        = DateTime.now()
        );
        insert log;

        Id jobId = System.enqueueJob(new ExtoleBackfillQueueable(
            log.Id, objectType, audienceType, selectedDate, reportId, targetField, programLabel, null
        ));

        log.Batch_Job_Id__c = jobId;
        update log;

        return log.Id;
    }

    private static void persistShareLinkFieldSetting(String objectType, String fieldName) {
        if (String.isBlank(fieldName)) return;
        Extole_App_Settings__c s = Extole_App_Settings__c.getOrgDefaults();
        if (s.Id == null) s = new Extole_App_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
        if (objectType == 'Lead') s.Lead_Share_Link_Field__c = fieldName;
        else                      s.Contact_Share_Link_Field__c = fieldName;
        upsert s;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Log queries (for Backfill tab Last Run panel)
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static Extole_Backfill_Log__c getLastBackfillRun() {
        List<Extole_Backfill_Log__c> logs = [
            SELECT Id, Name, Object_Type__c, Audience_Type__c, Audience_Criteria__c,
                   Target_Field__c, Program_Label__c, Status__c, Started_At__c, Completed_At__c,
                   Total_Count__c, Success_Count__c, Error_Count__c, Error_Detail__c,
                   Batch_Job_Id__c
            FROM Extole_Backfill_Log__c
            ORDER BY Started_At__c DESC
            LIMIT 1
        ];
        return logs.isEmpty() ? null : logs[0];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Log queries (for Settings Diagnostics)
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<Extole_Backfill_Log__c> getBackfillLogs() {
        return [
            SELECT Id, Name, Object_Type__c, Audience_Type__c, Audience_Criteria__c,
                   Target_Field__c, Program_Label__c, Status__c, Started_At__c, Completed_At__c,
                   Total_Count__c, Success_Count__c, Error_Count__c, Error_Detail__c
            FROM Extole_Backfill_Log__c
            ORDER BY Started_At__c DESC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=false)
    public static void clearBackfillLogs() {
        List<Extole_Backfill_Log__c> all = [SELECT Id FROM Extole_Backfill_Log__c LIMIT 10000];
        if (!all.isEmpty()) delete all;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static Integer countFromDefaultFilter(String objectType) {
        try {
            if (objectType == 'Contact') {
                return [
                    SELECT COUNT() FROM Contact
                    WHERE Email != null
                    AND Id IN (SELECT ContactId FROM Opportunity WHERE StageName = 'Closed Won' AND ContactId != null)
                ];
            } else {
                return [SELECT COUNT() FROM Lead WHERE Email != null AND IsConverted = false];
            }
        } catch (Exception e) {
            throw new AuraHandledException('Count query failed: ' + e.getMessage());
        }
    }

    private static Integer countFromDateFilter(String objectType, String selectedDate) {
        try {
            Date d = Date.valueOf(selectedDate);
            if (objectType == 'Contact') {
                return Database.countQuery(
                    'SELECT COUNT() FROM Contact WHERE Email != null AND CreatedDate >= :d'
                );
            } else {
                return Database.countQuery(
                    'SELECT COUNT() FROM Lead WHERE Email != null AND IsConverted = false AND CreatedDate >= :d'
                );
            }
        } catch (Exception e) {
            throw new AuraHandledException('Count query failed: ' + e.getMessage());
        }
    }

    private static Integer countFromReport(String reportId) {
        try {
            Reports.ReportResults rr = Reports.ReportManager.runReport(reportId, true);
            Reports.ReportFactWithDetails facts = (Reports.ReportFactWithDetails) rr.getFactMap().get('T!T');
            return facts != null ? facts.getRows().size() : 0;
        } catch (Exception e) {
            throw new AuraHandledException('Report count failed: ' + e.getMessage());
        }
    }

    private static String defaultFilterDescription(String objectType) {
        return objectType == 'Contact'
            ? 'Contacts with email on Closed Won opportunities'
            : 'Unconverted leads with email';
    }

    private class FieldLabelComparator implements Comparator<Map<String, String>> {
        public Integer compare(Map<String, String> a, Map<String, String> b) {
            return a.get('label').compareTo(b.get('label'));
        }
    }
}
