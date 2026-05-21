/**
 * ExtoleWebhookController
 *
 * Apex REST endpoint that receives outbound webhooks from the Extole platform
 * and writes event data to Salesforce Contact or Lead records based on active
 * Extole_Writeback_Cfg__c rules.
 *
 * URL: /services/apexrest/extole/events
 * Auth: Salesforce OAuth 2.0 client credentials (Connected App configured in Extole)
 *
 * Payload schema:
 *   { "event_id": "...", "event_name": "reward_earned", "data": { "email": "...", "salesforce_id": "...", ... } }
 *
 * Field mappings (Extole_Writeback_Cfg__c.Field_Mappings__c) are a JSON array:
 *   [{ "extoleKey": "value", "sfdcField": "Extole_Reward_Value__c" }, ...]
 */
@RestResource(urlMapping='/extole/events')
global without sharing class ExtoleWebhookController {

    @HttpPost
    global static void doPost() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String rawPayload = req.requestBody != null ? req.requestBody.toString() : '';

        // ── Parse payload ──────────────────────────────────────────────────────
        String eventName;
        String eventId;
        String email;
        String salesforceId;
        Map<String, Object> data;

        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(rawPayload);
            eventName    = (String) body.get('event_name');
            eventId      = (String) body.get('event_id');
            data         = body.containsKey('data')
                ? (Map<String, Object>) body.get('data')
                : new Map<String, Object>();
            email        = (String) data.get('email');
            salesforceId = (String) data.get('salesforce_id');
        } catch (Exception e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('{"error":"invalid_payload"}');
            return;
        }

        if (String.isBlank(eventName)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('{"error":"missing_event_name"}');
            return;
        }

        // ── Idempotency: skip duplicate event_ids ──────────────────────────────
        if (String.isNotBlank(eventId)) {
            List<Extole_Writeback_Log__c> prior = [
                SELECT Id FROM Extole_Writeback_Log__c
                WHERE Event_Id__c = :eventId AND Status__c != 'FAILED'
                LIMIT 1
            ];
            if (!prior.isEmpty()) {
                res.statusCode = 200;
                res.responseBody = Blob.valueOf('{"status":"duplicate"}');
                return;
            }
        }

        // ── Find matching active writeback configs ─────────────────────────────
        List<Extole_Writeback_Cfg__c> configs = [
            SELECT Id, Object_Type__c, Field_Mappings__c
            FROM Extole_Writeback_Cfg__c
            WHERE Event_Name__c = :eventName AND Status__c = 'ACTIVE'
            LIMIT 50
        ];

        if (configs.isEmpty()) {
            safeWriteLog(eventName, eventId, email, salesforceId, null, null,
                         'SKIPPED', 'No active writeback config for: ' + eventName, rawPayload);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"status":"skipped","reason":"no_config"}');
            return;
        }

        // ── Apply each matching config ─────────────────────────────────────────
        List<Extole_Writeback_Log__c> logs = new List<Extole_Writeback_Log__c>();

        for (Extole_Writeback_Cfg__c cfg : configs) {
            String objType    = cfg.Object_Type__c;
            String status     = 'SUCCESS';
            String errDetail  = null;
            String recordId   = null;

            try {
                SObject record = findRecord(objType, email, salesforceId);
                if (record == null) {
                    status    = 'SKIPPED';
                    errDetail = 'No matching ' + objType
                        + ' found — email=' + email
                        + ' salesforceId=' + salesforceId;
                } else {
                    recordId = (String) record.get('Id');
                    applyMappings(record, cfg.Field_Mappings__c, data);
                    update record;
                }
            } catch (Exception e) {
                status    = 'FAILED';
                errDetail = e.getMessage();
            }

            logs.add(buildLog(eventName, eventId, email, salesforceId,
                              objType, recordId, status, errDetail, rawPayload));
        }

        if (!logs.isEmpty()) {
            try { insert logs; } catch (Exception e) {
                System.debug('ExtoleWebhookController: log insert failed — ' + e.getMessage());
            }
        }

        res.statusCode = 200;
        res.responseBody = Blob.valueOf('{"status":"ok","processed":' + logs.size() + '}');
    }

    // ── Record lookup ──────────────────────────────────────────────────────────

    @TestVisible
    private static SObject findRecord(String objectType, String email, String salesforceId) {
        if (objectType == 'Contact') {
            if (String.isNotBlank(salesforceId)) {
                List<Contact> r = [SELECT Id FROM Contact WHERE Id = :salesforceId LIMIT 1];
                if (!r.isEmpty()) return r[0];
            }
            if (String.isNotBlank(email)) {
                List<Contact> r = [SELECT Id FROM Contact WHERE Email = :email ORDER BY CreatedDate DESC LIMIT 1];
                if (!r.isEmpty()) return r[0];
            }
        } else if (objectType == 'Lead') {
            if (String.isNotBlank(salesforceId)) {
                List<Lead> r = [SELECT Id FROM Lead WHERE Id = :salesforceId AND IsConverted = false LIMIT 1];
                if (!r.isEmpty()) return r[0];
            }
            if (String.isNotBlank(email)) {
                List<Lead> r = [SELECT Id FROM Lead WHERE Email = :email AND IsConverted = false ORDER BY CreatedDate DESC LIMIT 1];
                if (!r.isEmpty()) return r[0];
            }
        }
        return null;
    }

    // ── Field mapping ──────────────────────────────────────────────────────────

    @TestVisible
    private static void applyMappings(SObject record, String mappingsJson, Map<String, Object> data) {
        if (String.isBlank(mappingsJson)) return;
        List<Object> mappings;
        try {
            mappings = (List<Object>) JSON.deserializeUntyped(mappingsJson);
        } catch (Exception e) {
            throw new ExtoleApiException('Invalid field mappings JSON: ' + e.getMessage());
        }
        for (Object m : mappings) {
            Map<String, Object> mapping = (Map<String, Object>) m;
            String extoleKey = (String) mapping.get('extoleKey');
            String sfdcField = (String) mapping.get('sfdcField');
            if (String.isBlank(extoleKey) || String.isBlank(sfdcField)) continue;
            Object val = data.get(extoleKey);
            if (val == null) continue;
            try {
                record.put(sfdcField, String.valueOf(val));
            } catch (Exception e) {
                System.debug('ExtoleWebhookController: could not set ' + sfdcField + ': ' + e.getMessage());
            }
        }
    }

    // ── Log helpers ────────────────────────────────────────────────────────────

    private static Extole_Writeback_Log__c buildLog(
        String eventName, String eventId, String email, String salesforceId,
        String objectType, String recordId, String status, String error, String payload
    ) {
        Extole_Writeback_Log__c log = new Extole_Writeback_Log__c();
        log.Event_Name__c    = eventName;
        log.Event_Id__c      = eventId;
        log.Email__c         = email;
        log.Salesforce_Id__c = salesforceId;
        log.Object_Type__c   = objectType;
        log.Record_Id__c     = recordId;
        log.Status__c        = status;
        log.Error__c         = error;
        log.Payload__c       = payload != null && payload.length() > 32768
            ? payload.substring(0, 32768) : payload;
        log.Received_At__c   = System.now();
        return log;
    }

    private static void safeWriteLog(
        String eventName, String eventId, String email, String salesforceId,
        String objectType, String recordId, String status, String error, String payload
    ) {
        try {
            insert buildLog(eventName, eventId, email, salesforceId,
                            objectType, recordId, status, error, payload);
        } catch (Exception e) {
            System.debug('ExtoleWebhookController: safeWriteLog failed — ' + e.getMessage());
        }
    }
}
