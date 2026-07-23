public with sharing class ExtoleAudienceController {
    @AuraEnabled(cacheable=false)
    public static List<Extole_Audience_Cfg__c> getAudienceConfigs() {
        try {
            ExtoleLogPurgeJob.ensureScheduled();
        } catch (Exception e) {
            System.debug(
                'ExtoleAudienceController.getAudienceConfigs: could not ensure log purge job scheduled — ' +
                e.getMessage()
            );
        }
        return [
            SELECT
                Id,
                Name,
                CreatedDate,
                LastModifiedDate,
                Config_Key__c,
                Extole_Audience_Name__c,
                Extole_Audience_Id__c,
                Source_Report_Id__c,
                Source_Report_Name__c,
                Identity_Column__c,
                Sync_Cadence__c,
                Active__c,
                Last_Sync_At__c,
                Last_Operation_Id__c,
                Last_Operation_State__c,
                Last_Member_Count__c,
                Last_Error__c
            FROM Extole_Audience_Cfg__c
            ORDER BY Extole_Audience_Name__c ASC
        ];
    }

    @AuraEnabled
    public static Id saveAudienceConfig(Extole_Audience_Cfg__c config) {
        if (config == null) {
            throw new AuraHandledException('config is required');
        }
        if (String.isBlank(config.Extole_Audience_Name__c)) {
            throw new AuraHandledException('Extole audience name is required');
        }
        if (String.isBlank(config.Source_Report_Id__c)) {
            throw new AuraHandledException('Source report is required');
        }
        if (String.isBlank(config.Identity_Column__c)) {
            throw new AuraHandledException('Identity column is required');
        }
        if (String.isBlank(config.Config_Key__c)) {
            config.Config_Key__c = generateConfigKey(
                config.Extole_Audience_Name__c
            );
        }
        try {
            upsert config Config_Key__c;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'Failed to save audience config: ' + e.getMessage()
            );
        }
        if (
            String.isNotBlank(config.Sync_Cadence__c) &&
            config.Sync_Cadence__c != 'Manual'
        ) {
            ExtoleAudienceScheduler.ensureScheduled();
        }
        return config.Id;
    }

    @AuraEnabled
    public static void runSchedulerNow() {
        new ExtoleAudienceScheduler().execute(null);
    }

    @AuraEnabled
    public static void deleteAudienceConfig(Id configId) {
        if (configId == null)
            throw new AuraHandledException('configId is required');
        try {
            delete [SELECT Id FROM Extole_Audience_Cfg__c WHERE Id = :configId];
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to delete audience config: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getAvailableReports() {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Report r : [
            SELECT Id, Name, DeveloperName, Format
            FROM Report
            WHERE Format = 'Tabular'
            ORDER BY Name ASC
            LIMIT 500
        ]) {
            result.add(
                new Map<String, Object>{
                    'id' => String.valueOf(r.Id),
                    'name' => r.Name,
                    'developerName' => r.DeveloperName,
                    'format' => r.Format
                }
            );
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getReportColumns(Id reportId) {
        if (reportId == null)
            throw new AuraHandledException('reportId is required');
        try {
            Reports.ReportDescribeResult describe = Reports.ReportManager.describeReport(
                reportId
            );
            return describe.getReportMetadata().getDetailColumns();
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to describe report: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled
    public static Id syncAudience(String configKey) {
        if (String.isBlank(configKey))
            throw new AuraHandledException('configKey is required');
        List<Extole_Audience_Cfg__c> configs = [
            SELECT Id, Config_Key__c, Last_Operation_State__c
            FROM Extole_Audience_Cfg__c
            WHERE Config_Key__c = :configKey
            LIMIT 1
            FOR UPDATE
        ];
        if (configs.isEmpty()) {
            throw new AuraHandledException(
                'Audience config not found: ' + configKey
            );
        }
        String prior = configs[0].Last_Operation_State__c;
        if (
            prior == 'PREPARING' ||
            prior == 'BUILDING' ||
            prior == 'VALIDATING'
        ) {
            throw new AuraHandledException(
                'A previous sync is still in progress (' +
                    prior +
                    '). Wait for it to finish before syncing again.'
            );
        }
        configs[0].Last_Operation_State__c = 'PREPARING';
        configs[0].Last_Error__c = null;
        update configs[0];

        return System.enqueueJob(new ExtoleAudienceSyncQueueable(configKey));
    }

    @AuraEnabled
    public static Extole_Audience_Cfg__c pollAudienceState(String configKey) {
        if (String.isBlank(configKey))
            throw new AuraHandledException('configKey is required');
        List<Extole_Audience_Cfg__c> configs = [
            SELECT
                Id,
                Config_Key__c,
                Extole_Audience_Name__c,
                Extole_Audience_Id__c,
                Source_Report_Id__c,
                Source_Report_Name__c,
                Identity_Column__c,
                Sync_Cadence__c,
                Active__c,
                Last_Sync_At__c,
                Last_Operation_Id__c,
                Last_Operation_State__c,
                Last_Member_Count__c,
                Last_Error__c
            FROM Extole_Audience_Cfg__c
            WHERE Config_Key__c = :configKey
            LIMIT 1
        ];
        if (configs.isEmpty())
            throw new AuraHandledException(
                'Audience config not found: ' + configKey
            );

        Extole_Audience_Cfg__c config = configs[0];
        String state = config.Last_Operation_State__c;
        Boolean shouldPoll =
            String.isNotBlank(config.Last_Operation_Id__c) &&
            String.isNotBlank(config.Extole_Audience_Id__c) &&
            (state == 'PREPARING' ||
            state == 'BUILDING' ||
            state == 'VALIDATING');
        if (!shouldPoll)
            return config;

        String previousState = state;
        try {
            ExtoleConfig extoleConfig = new ExtoleConfig('Extole_API');
            ExtoleClient client = new ExtoleClient();
            HttpRequest request = new ExtoleAudienceOperationStateRequest(
                    config.Extole_Audience_Id__c,
                    config.Last_Operation_Id__c
                )
                .build(extoleConfig);
            HttpResponse httpResponse = client.send(extoleConfig, request);
            ExtoleAudienceOperationStateResponse response = ExtoleAudienceOperationStateResponse.fromResponse(
                httpResponse
            );

            String newState = response.operation.state;
            config.Last_Operation_State__c = newState;
            if (response.isTerminal()) {
                config.Last_Sync_At__c = DateTime.now();
                if (!response.isSuccess()) {
                    config.Last_Error__c = 'Operation FAILED — check Extole for details.';
                }
            }
            update config;

            if (previousState != newState && response.isTerminal()) {
                String detail = response.isSuccess()
                    ? 'Sync complete'
                    : 'Sync failed';
                writeLog(
                    config.Config_Key__c,
                    config.Extole_Audience_Id__c,
                    config.Last_Operation_Id__c,
                    'REPLACE',
                    newState,
                    config.Last_Member_Count__c,
                    detail,
                    config.Last_Error__c
                );
            }
        } catch (Exception e) {
            System.debug('pollAudienceState ERROR: ' + e.getMessage());
        }
        return config;
    }

    @AuraEnabled(cacheable=false)
    public static List<Extole_Audience_Sync_Log__c> getAudienceSyncLogs() {
        return [
            SELECT
                Id,
                Name,
                Config_Key__c,
                Audience_Id__c,
                Operation_Id__c,
                Operation_Type__c,
                State__c,
                Member_Count__c,
                Timestamp__c,
                Detail__c
            FROM Extole_Audience_Sync_Log__c
            ORDER BY Timestamp__c DESC
            LIMIT 500
        ];
    }

    @AuraEnabled
    public static Map<String, Integer> clearAudienceSyncLogs() {
        try {
            List<Extole_Audience_Sync_Log__c> logs = [
                SELECT Id
                FROM Extole_Audience_Sync_Log__c
                LIMIT 10000
            ];
            Integer deletedCount = logs.size();
            if (!logs.isEmpty())
                delete logs;
            Integer remaining = [
                SELECT COUNT()
                FROM Extole_Audience_Sync_Log__c
            ];
            return new Map<String, Integer>{
                'deletedCount' => deletedCount,
                'remainingCount' => remaining
            };
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to clear audience sync log: ' + e.getMessage()
            );
        }
    }

    public static void writeLog(
        String configKey,
        String audienceId,
        String operationId,
        String operationType,
        String state,
        Decimal memberCount,
        String detail,
        String errorText
    ) {
        try {
            insert new Extole_Audience_Sync_Log__c(
                Config_Key__c = configKey,
                Audience_Id__c = audienceId,
                Operation_Id__c = operationId,
                Operation_Type__c = operationType,
                State__c = state,
                Member_Count__c = memberCount,
                Timestamp__c = DateTime.now(),
                Detail__c = errorText != null
                    ? (detail + ' | ' + errorText)
                    : detail
            );
        } catch (Exception e) {
            System.debug(
                'ExtoleAudienceController.writeLog ERROR: ' + e.getMessage()
            );
        }
    }

    private static String generateConfigKey(String audienceName) {
        String slug = audienceName == null
            ? 'audience'
            : audienceName.replaceAll('[^a-zA-Z0-9_]', '_');
        return slug + '_' + DateTime.now().getTime();
    }
}
