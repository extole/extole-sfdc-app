/**
 * ExtoleUniversalHandler
 *
 * Single Queueable handler that replaces per-config generated Apex classes.
 * Invoked by Record-Triggered Flows via @InvocableMethod.
 *
 * The Flow passes two inputs:
 *   configKey  — the Config_Key__c of the Extole_Event_Cfg__c record (static string in the Flow)
 *   recordId   — the triggering record's Id ($Record.Id)
 *
 * At runtime, this class:
 *   1. Loads the active Extole_Event_Cfg__c for the given configKey
 *   2. Builds a SOQL query from the stored field mappings
 *   3. Queries the triggering record(s)
 *   4. Sends an event to the Extole API for each record
 *   5. Updates telemetry on the config record
 */
public with sharing class ExtoleUniversalHandler implements Queueable, Database.AllowsCallouts {

    private static final Integer CALLOUT_CHUNK_SIZE = 100;

    private String configKey;
    private List<String> recordIds;

    public ExtoleUniversalHandler(String configKey, List<String> recordIds) {
        this.configKey = configKey;
        this.recordIds = recordIds;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // @InvocableMethod — called by Record-Triggered Flow
    // ─────────────────────────────────────────────────────────────────────────

    public class HandlerInput {
        @InvocableVariable(required=true label='Config Key')
        public String configKey;
        @InvocableVariable(required=true label='Record ID')
        public String recordId;
    }

    @InvocableMethod(label='Invoke Extole Handler' description='Sends an Extole event for the triggering record')
    public static void invoke(List<HandlerInput> inputs) {
        if (inputs == null || inputs.isEmpty()) return;

        // Group record IDs by configKey so we enqueue one job per config
        Map<String, List<String>> byConfig = new Map<String, List<String>>();
        for (HandlerInput inp : inputs) {
            if (String.isBlank(inp.configKey) || String.isBlank(inp.recordId)) continue;
            if (!byConfig.containsKey(inp.configKey)) {
                byConfig.put(inp.configKey, new List<String>());
            }
            byConfig.get(inp.configKey).add(inp.recordId);
        }

        for (String key : byConfig.keySet()) {
            List<String> allIds = byConfig.get(key);
            for (Integer i = 0; i < allIds.size(); i += CALLOUT_CHUNK_SIZE) {
                Integer chunkEnd = Math.min(i + CALLOUT_CHUNK_SIZE, allIds.size());
                List<String> chunk = new List<String>();
                for (Integer j = i; j < chunkEnd; j++) {
                    chunk.add(allIds.get(j));
                }
                System.enqueueJob(new ExtoleUniversalHandler(key, chunk));
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Queueable execute — runs with full callout access
    // ─────────────────────────────────────────────────────────────────────────

    public void execute(QueueableContext ctx) {
        // 1. Load the active config record
        List<Extole_Event_Cfg__c> configs = [
            SELECT Id, Config_Key__c, Event_Name__c, Trigger_Object__c, Field_Mappings_JSON__c,
                   Last_Attempted_At__c, Last_Succeeded_At__c, Last_Failed_At__c,
                   Last_Record_Id__c, Last_HTTP_Status__c, Last_Response_Summary__c
            FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = :configKey AND Active__c = true
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            System.debug('ExtoleUniversalHandler.execute: no active config found for configKey=' + configKey);
            return;
        }
        Extole_Event_Cfg__c cfg = configs[0];

        // 2. Parse field mappings
        List<Object> mappings;
        try {
            mappings = (List<Object>) JSON.deserializeUntyped(cfg.Field_Mappings_JSON__c);
        } catch (Exception e) {
            System.debug('ExtoleUniversalHandler.execute: invalid field mappings JSON: ' + e.getMessage());
            return;
        }

        // 3. Build SOQL field set (always include Id; add any sfdc_field paths)
        Set<String> fieldSet = new Set<String>{ 'Id' };
        for (Object rawM : mappings) {
            Map<String, Object> m = (Map<String, Object>) rawM;
            String sfdcField = (String) m.get('sfdc_field');
            if (!String.isBlank(sfdcField)) {
                fieldSet.add(sfdcField); // SOQL handles dot-notation natively
            }
        }
        String soql = 'SELECT ' + String.join(new List<String>(fieldSet), ', ')
            + ' FROM ' + cfg.Trigger_Object__c + ' WHERE Id IN :recordIds';

        // 4. Query records
        List<SObject> records;
        try {
            records = Database.query(soql);
        } catch (Exception e) {
            System.debug('ExtoleUniversalHandler.execute: SOQL failed – ' + e.getMessage());
            return;
        }

        // 5. Send one Extole event per record
        // Telemetry is accumulated and written once after the loop to avoid N+1 DML.
        DateTime lastAttemptedAt = null;
        String   lastRecordId    = null;
        Boolean  lastSuccess     = null;
        Integer  lastHttpStatus  = null;
        String   lastSummary     = null;

        for (SObject r : records) {
            Map<String, Object> dataMap = buildDataMap(r, mappings);
            dataMap.put('app_type', 'salesforce_crm');

            Map<String, Object> payload = new Map<String, Object>{
                'event_name' => cfg.Event_Name__c,
                'data'       => dataMap
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Extole_API/v5/events');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(payload));
            req.setTimeout(30000);

            DateTime attemptedAt = DateTime.now();
            HttpResponse res;
            try {
                res = new Http().send(req);
            } catch (Exception e) {
                lastAttemptedAt = attemptedAt;
                lastRecordId    = (String) r.get('Id');
                lastSuccess     = false;
                lastHttpStatus  = null;
                lastSummary     = 'Callout exception: ' + e.getMessage();
                continue;
            }

            Boolean success = (res.getStatusCode() >= 200 && res.getStatusCode() < 300);
            String summary = 'HTTP ' + res.getStatusCode();
            if (!success) {
                String respBody = res.getBody();
                summary += ': ' + (respBody != null && respBody.length() > 200
                    ? respBody.substring(0, 200) : respBody);
            }

            lastAttemptedAt = attemptedAt;
            lastRecordId    = (String) r.get('Id');
            lastSuccess     = success;
            lastHttpStatus  = res.getStatusCode();
            lastSummary     = summary;
        }

        // Single DML write after all callouts complete
        if (lastAttemptedAt != null) {
            updateTelemetry(cfg, lastRecordId, lastAttemptedAt,
                lastSuccess, lastHttpStatus, lastSummary);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Build the Extole event data map for a single record.
     * Handles direct fields, one-hop relationship fields (e.g. "Account.Name"),
     * and static values. Null field values are omitted.
     */
    private static Map<String, Object> buildDataMap(SObject r, List<Object> mappings) {
        Map<String, Object> dataMap = new Map<String, Object>();

        for (Object rawM : mappings) {
            Map<String, Object> m = (Map<String, Object>) rawM;
            String extoleParam = (String) m.get('extole_param');
            String sfdcField   = (String) m.get('sfdc_field');
            String staticValue = (String) m.get('static_value');

            if (String.isBlank(extoleParam)) continue;

            if (!String.isBlank(staticValue)) {
                dataMap.put(extoleParam, staticValue);
            } else if (!String.isBlank(sfdcField)) {
                if (sfdcField.contains('.')) {
                    // One-hop relationship field: e.g. "Account.Name"
                    String[] parts = sfdcField.split('\\.', 2);
                    SObject rel = r.getSObject(parts[0]);
                    if (rel != null) {
                        Object fv = rel.get(parts[1]);
                        if (fv != null) dataMap.put(extoleParam, fv);
                    }
                } else {
                    Object fv = r.get(sfdcField);
                    if (fv != null) dataMap.put(extoleParam, fv);
                }
            }
        }

        return dataMap;
    }

    /**
     * Write last-run telemetry back to the config record.
     * Failure here is non-fatal — log and continue.
     */
    private static void updateTelemetry(
        Extole_Event_Cfg__c cfg,
        String recordId,
        DateTime attemptedAt,
        Boolean success,
        Integer httpStatus,
        String responseSummary
    ) {
        try {
            cfg.Last_Attempted_At__c     = attemptedAt;
            cfg.Last_Record_Id__c        = recordId;
            cfg.Last_HTTP_Status__c      = httpStatus;
            cfg.Last_Response_Summary__c = responseSummary;
            if (success) {
                cfg.Last_Succeeded_At__c = attemptedAt;
            } else {
                cfg.Last_Failed_At__c = attemptedAt;
            }
            update cfg;
        } catch (Exception e) {
            System.debug('ExtoleUniversalHandler.updateTelemetry ERROR: ' + e.getMessage());
        }
    }
}
