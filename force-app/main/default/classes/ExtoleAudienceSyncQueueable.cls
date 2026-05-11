/**
 * ExtoleAudienceSyncQueueable
 *
 * Runs one audience sync end-to-end:
 *   1. Load Extole_Audience_Cfg__c by configKey
 *   2. Run the configured Salesforce report and extract identity column values
 *   3. Resolve (or create) the audience in Extole — by name
 *   4. Submit a REPLACE operation with the email list
 *   5. Persist operation ID + state on the config record; write a sync log row
 *
 * The Extole audience operation is asynchronous; the LWC polls via
 * ExtoleAudienceController.pollAudienceState to surface progress.
 */
public with sharing class ExtoleAudienceSyncQueueable implements Queueable, Database.AllowsCallouts {

    private final String configKey;

    public ExtoleAudienceSyncQueueable(String configKey) {
        this.configKey = configKey;
    }

    public void execute(QueueableContext ctx) {
        List<Extole_Audience_Cfg__c> configs = [
            SELECT Id, Config_Key__c, Extole_Audience_Name__c, Extole_Audience_Id__c,
                   Source_Report_Id__c, Identity_Column__c,
                   Last_Operation_Id__c, Last_Operation_State__c, Last_Error__c, Last_Member_Count__c
            FROM Extole_Audience_Cfg__c
            WHERE Config_Key__c = :configKey
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            System.debug('ExtoleAudienceSyncQueueable: no config for ' + configKey);
            return;
        }
        Extole_Audience_Cfg__c cfg = configs[0];

        // 1. Pull rows from the configured report
        List<String> emails;
        try {
            emails = runReportAndCollectIdentities(cfg.Source_Report_Id__c, cfg.Identity_Column__c);
        } catch (Exception e) {
            markFailed(cfg, 'Failed to read report: ' + e.getMessage());
            return;
        }
        if (emails.isEmpty()) {
            markFailed(cfg, 'Report returned 0 rows for column ' + cfg.Identity_Column__c);
            return;
        }

        // 2. Resolve audience id from name (create if missing)
        ExtoleConfig extoleConfig = new ExtoleConfig('Extole_API');
        ExtoleClient client = new ExtoleClient();
        String audienceId;
        try {
            audienceId = resolveAudienceId(client, extoleConfig, cfg.Extole_Audience_Name__c);
        } catch (Exception e) {
            markFailed(cfg, 'Failed to resolve audience: ' + e.getMessage());
            return;
        }
        cfg.Extole_Audience_Id__c = audienceId;

        // 3. Submit REPLACE operation
        try {
            HttpRequest req = new ExtoleAudienceOperationRequest(
                audienceId, ExtoleAudienceOperationRequest.TYPE_REPLACE
            ).withEmails(emails).build(extoleConfig);
            HttpResponse res = client.send(extoleConfig, req);
            ExtoleAudienceOperationResponse resp = ExtoleAudienceOperationResponse.fromResponse(res);

            String submittedState = String.isNotBlank(resp.operation.state)
                ? resp.operation.state : 'PREPARING';
            cfg.Last_Operation_Id__c    = resp.operation.operationId;
            cfg.Last_Operation_State__c = submittedState;
            cfg.Last_Member_Count__c    = emails.size();
            cfg.Last_Error__c           = null;
            cfg.Last_Sync_At__c         = DateTime.now();
            update cfg;

            ExtoleAudienceController.writeLog(
                cfg.Config_Key__c, audienceId, resp.operation.operationId,
                'REPLACE', submittedState, emails.size(),
                'Operation submitted with ' + emails.size() + ' members', null
            );
        } catch (Exception e) {
            markFailed(cfg, 'Failed to submit operation: ' + e.getMessage());
        }
    }

    private static String resolveAudienceId(ExtoleClient client, ExtoleConfig config, String name) {
        HttpRequest listReq = new ExtoleListAudiencesRequest().build(config);
        HttpResponse listRes = client.send(config, listReq);
        ExtoleListAudiencesResponse listResp = ExtoleListAudiencesResponse.fromResponse(listRes);
        ExtoleAudience existing = listResp.findByName(name);
        if (existing != null) return existing.audienceId;

        HttpRequest createReq = new ExtoleCreateAudienceRequest(name).build(config);
        HttpResponse createRes = client.send(config, createReq);
        ExtoleCreateAudienceResponse createResp =
            ExtoleCreateAudienceResponse.fromResponse(createRes);
        return createResp.audience.audienceId;
    }

    private static List<String> runReportAndCollectIdentities(Id reportId, String columnName) {
        if (reportId == null || String.isBlank(columnName)) {
            throw new IllegalArgumentException('reportId and columnName are required');
        }
        Reports.ReportResults results = Reports.ReportManager.runReport(reportId, true);
        Reports.ReportFactWithDetails facts =
            (Reports.ReportFactWithDetails) results.getFactMap().get('T!T');
        if (facts == null) return new List<String>();

        // Find the column index by api name
        List<String> cols = results.getReportMetadata().getDetailColumns();
        Integer idx = -1;
        for (Integer i = 0; i < cols.size(); i++) {
            if (columnName.equals(cols.get(i))) {
                idx = i;
                break;
            }
        }
        if (idx < 0) {
            throw new IllegalArgumentException('Column ' + columnName + ' not found in report');
        }

        Set<String> seen = new Set<String>();
        for (Reports.ReportDetailRow row : facts.getRows()) {
            List<Reports.ReportDataCell> cells = row.getDataCells();
            if (idx >= cells.size()) continue;
            Object raw = cells.get(idx).getValue();
            if (raw == null) continue;
            String s = String.valueOf(raw).trim();
            if (s.length() > 0) seen.add(s);
        }
        return new List<String>(seen);
    }

    private static void markFailed(Extole_Audience_Cfg__c cfg, String message) {
        cfg.Last_Operation_State__c = 'FAILED';
        cfg.Last_Error__c           = message != null && message.length() > 32000
            ? message.substring(0, 32000) : message;
        cfg.Last_Sync_At__c         = DateTime.now();
        try {
            update cfg;
        } catch (Exception ignored) { }
        ExtoleAudienceController.writeLog(
            cfg.Config_Key__c, cfg.Extole_Audience_Id__c, cfg.Last_Operation_Id__c,
            'REPLACE', 'FAILED', cfg.Last_Member_Count__c, 'Sync failed', message
        );
    }

    public class IllegalArgumentException extends Exception {}
}
