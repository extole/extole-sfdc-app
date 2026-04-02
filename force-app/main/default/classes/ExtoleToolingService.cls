/**
 * ExtoleToolingService
 *
 * Generates and deploys Apex handler classes via the Salesforce Tooling API.
 * Authentication uses UserInfo.getSessionId() — no Connected App required.
 * The running admin must have "Author Apex" permission.
 *
 * Handler naming convention:
 *   Extole_Handler_[ConfigKey]        (initial deploy, version 1)
 *   Extole_Handler_[ConfigKey]_v2     (second deploy)
 *   Extole_Handler_[ConfigKey]_v3     (third deploy) … and so on
 *
 * Generated handler pattern: Queueable + Database.AllowsCallouts (never @future).
 */
public with sharing class ExtoleToolingService {

    // Tooling API base path — constructed at runtime using the org's instance URL
    private static String toolingBaseUrl() {
        return URL.getOrgDomainUrl().toExternalForm() + '/services/data/v59.0/tooling';
    }

    // Set by ExtoleEventController before making callouts — provides the full
    // API-capable session obtained via the VF page postMessage trick.
    public static String sessionOverride = null;

    private static String getSessionId() {
        if (!String.isBlank(sessionOverride)) return sessionOverride;
        try {
            Map<String, String> session = Auth.SessionManagement.getCurrentSession();
            String sid = session != null ? session.get('SessionId') : null;
            if (!String.isBlank(sid)) return sid;
        } catch (Exception e) {
            System.debug('ExtoleToolingService.getSessionId: Auth.SessionManagement failed – ' + e.getMessage());
        }
        return UserInfo.getSessionId();
    }

    private static String sessionHeader() {
        return 'Bearer ' + getSessionId();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Public interface
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Deploy a generated handler class to the org via Tooling API.
     *
     * @param configKey       Stable config key derived from CMDT developer name
     * @param version         Config version number (1 = no suffix, 2+ = _v2, _v3 …)
     * @param triggerObject   SFDC object API name (e.g. 'Lead')
     * @param fields          Comma-separated list of fields to SELECT (may include one-hop paths)
     * @param eventName       Extole event_name value
     * @param fieldMappingsJSON  Serialized field mapping array (stored in CMDT)
     * @return Tooling API ApexClass Id of the newly created/updated class
     */
    public static String deployHandlerClass(
        String configKey,
        Integer version,
        String triggerObject,
        String fields,
        String eventName,
        String fieldMappingsJSON
    ) {
        String className = buildClassName(configKey, version);
        String body      = generateHandlerBody(className, triggerObject, fields, eventName, fieldMappingsJSON);

        // Check whether the class already exists (re-deploy scenario)
        String existingId = getApexClassId(className);

        if (existingId != null) {
            // PATCH to update the existing class body
            return patchApexClass(existingId, body);
        } else {
            // POST to create a new class
            return createApexClass(className, body);
        }
    }

    /**
     * Delete an Apex class by name.
     * Called on config delete for orphan cleanup (Settings → Clear orphaned handlers).
     *
     * @param className  Full class name (e.g. 'Extole_Handler_lead_created_a1b2_v2')
     */
    public static void deleteHandlerClass(String className) {
        String classId = getApexClassId(className);
        if (classId == null) {
            System.debug('ExtoleToolingService.deleteHandlerClass: class not found – ' + className);
            return;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(toolingBaseUrl() + '/sobjects/ApexClass/' + classId);
        req.setMethod('DELETE');
        req.setHeader('Authorization', sessionHeader());
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 204) {
            throw new ExtoleToolingException(
                'DELETE ApexClass failed: HTTP ' + res.getStatusCode() + ' – ' + res.getBody()
            );
        }
        System.debug('ExtoleToolingService.deleteHandlerClass: deleted ' + className + ' (Id=' + classId + ')');
    }

    /**
     * Look up an Apex class by name via Tooling API query.
     *
     * @param className  Full class name to look up
     * @return Tooling API record Id, or null if not found
     */
    public static String getApexClassId(String className) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            toolingBaseUrl() + '/query/?q=' +
            EncodingUtil.urlEncode(
                'SELECT Id FROM ApexClass WHERE Name = \'' + className + '\' LIMIT 1',
                'UTF-8'
            )
        );
        req.setMethod('GET');
        req.setHeader('Authorization', sessionHeader());
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            System.debug('ExtoleToolingService.getApexClassId: query failed HTTP '
                + res.getStatusCode() + ' ' + res.getBody());
            return null;
        }

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> records = (List<Object>) result.get('records');
        if (records == null || records.isEmpty()) {
            return null;
        }

        Map<String, Object> record = (Map<String, Object>) records[0];
        return (String) record.get('Id');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Class name helpers
    // ─────────────────────────────────────────────────────────────────────────

    public static String buildClassName(String configKey, Integer version) {
        if (version == null || version <= 1) {
            return 'Extole_Handler_' + configKey;
        }
        return 'Extole_Handler_' + configKey + '_v' + version;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Apex class body generation
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Generate the full Apex source for a handler class.
     *
     * Field mappings JSON shape (array of objects):
     *   [{"extole_param": "email", "sfdc_field": "Email", "static_value": null}, …]
     *
     * One-hop related fields are expressed as "Account.Name" — the SOQL SELECT
     * statement must already include the relationship path (passed in via `fields`).
     * The generated code resolves them via dynamic SObject field access.
     */
    @TestVisible
    static String generateHandlerBody(
        String className,
        String triggerObject,
        String fields,
        String eventName,
        String fieldMappingsJSON
    ) {
        List<Object> mappings = (List<Object>) JSON.deserializeUntyped(fieldMappingsJSON);

        // Build the data map construction lines
        String dataMapLines = buildDataMapLines(mappings, triggerObject);

        // The SELECT fields list — already validated and passed in
        String selectFields = fields;

        String body =
            'public with sharing class ' + className
            + ' implements Queueable, Database.AllowsCallouts {\n'
            + '\n'
            + '    private List<String> recordIds;\n'
            + '\n'
            + '    public ' + className + '(List<String> recordIds) {\n'
            + '        this.recordIds = recordIds;\n'
            + '    }\n'
            + '\n'
            + '    @InvocableMethod\n'
            + '    public static void invoke(List<String> recordIds) {\n'
            + '        System.enqueueJob(new ' + className + '(recordIds));\n'
            + '    }\n'
            + '\n'
            + '    public void execute(QueueableContext ctx) {\n'
            + '        List<SObject> records = Database.query(\n'
            + '            \'SELECT ' + selectFields + ' FROM ' + triggerObject + ' WHERE Id IN :recordIds\'\n'
            + '        );\n'
            + '\n'
            + '        // Look up the config record for telemetry updates\n'
            + '        String configKey = \'' + className + '\';\n'
            + '\n'
            + '        for (SObject r : records) {\n'
            + '            Map<String, Object> dataMap = new Map<String, Object>();\n'
            + dataMapLines
            + '            dataMap.put(\'app_type\', \'salesforce_crm\');\n'
            + '\n'
            + '            Map<String, Object> payload = new Map<String, Object>{\n'
            + '                \'event_name\' => \'' + escapeApexString(eventName) + '\',\n'
            + '                \'data\' => dataMap\n'
            + '            };\n'
            + '\n'
            + '            String bodyStr = JSON.serialize(payload);\n'
            + '\n'
            + '            HttpRequest req = new HttpRequest();\n'
            + '            req.setEndpoint(\'callout:Extole_API/v5/events\');\n'
            + '            req.setMethod(\'POST\');\n'
            + '            req.setHeader(\'Content-Type\', \'application/json\');\n'
            + '            req.setBody(bodyStr);\n'
            + '            req.setTimeout(30000);\n'
            + '\n'
            + '            DateTime attemptedAt = DateTime.now();\n'
            + '            HttpResponse res;\n'
            + '            try {\n'
            + '                res = new Http().send(req);\n'
            + '            } catch (Exception e) {\n'
            + '                ExtoleToolingService.updateConfigTelemetry(\n'
            + '                    \'' + escapeApexString(className) + '\',\n'
            + '                    (String) r.get(\'Id\'),\n'
            + '                    attemptedAt, false, null,\n'
            + '                    \'Callout exception: \' + e.getMessage()\n'
            + '                );\n'
            + '                continue;\n'
            + '            }\n'
            + '\n'
            + '            Boolean success = (res.getStatusCode() >= 200 && res.getStatusCode() < 300);\n'
            + '            String summary = \'HTTP \' + res.getStatusCode();\n'
            + '            if (!success) {\n'
            + '                String respBody = res.getBody();\n'
            + '                summary += \': \' + (respBody != null && respBody.length() > 200\n'
            + '                    ? respBody.substring(0, 200) : respBody);\n'
            + '            }\n'
            + '\n'
            + '            ExtoleToolingService.updateConfigTelemetry(\n'
            + '                \'' + escapeApexString(className) + '\',\n'
            + '                (String) r.get(\'Id\'),\n'
            + '                attemptedAt, success, res.getStatusCode(), summary\n'
            + '            );\n'
            + '        }\n'
            + '    }\n'
            + '}\n';

        return body;
    }

    /**
     * Build the Apex lines that populate dataMap from the field mappings.
     * Handles both direct fields and one-hop related fields (e.g. "Account.Name").
     * Null fields are omitted from the payload per spec.
     */
    private static String buildDataMapLines(List<Object> mappings, String triggerObject) {
        String lines = '';
        for (Object rawMapping : mappings) {
            Map<String, Object> m = (Map<String, Object>) rawMapping;
            String extoleParam  = (String) m.get('extole_param');
            String sfdcField    = (String) m.get('sfdc_field');
            String staticValue  = (String) m.get('static_value');

            if (String.isBlank(extoleParam)) continue;

            if (!String.isBlank(staticValue)) {
                // Static value — always inject
                lines += '            dataMap.put(\'' + escapeApexString(extoleParam) + '\', \''
                    + escapeApexString(staticValue) + '\');\n';
            } else if (!String.isBlank(sfdcField)) {
                if (sfdcField.contains('.')) {
                    // One-hop relationship field: e.g. "Account.Name"
                    String[] parts       = sfdcField.split('\\.', 2);
                    String relationName  = parts[0];
                    String childField    = parts[1];
                    lines += '            {\n'
                        + '                SObject rel = r.getSObject(\'' + escapeApexString(relationName) + '\');\n'
                        + '                if (rel != null) {\n'
                        + '                    Object fv = rel.get(\'' + escapeApexString(childField) + '\');\n'
                        + '                    if (fv != null) dataMap.put(\'' + escapeApexString(extoleParam) + '\', fv);\n'
                        + '                }\n'
                        + '            }\n';
                } else {
                    // Direct field
                    lines += '            {\n'
                        + '                Object fv = r.get(\'' + escapeApexString(sfdcField) + '\');\n'
                        + '                if (fv != null) dataMap.put(\'' + escapeApexString(extoleParam) + '\', fv);\n'
                        + '            }\n';
                }
            }
        }
        return lines;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Tooling API CRUD
    // ─────────────────────────────────────────────────────────────────────────

    private static String createApexClass(String className, String body) {
        Map<String, Object> payload = new Map<String, Object>{
            'Name'       => className,
            'Body'       => body,
            'ApiVersion' => 59.0
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(toolingBaseUrl() + '/sobjects/ApexClass/');
        req.setMethod('POST');
        req.setHeader('Authorization', sessionHeader());
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(60000);

        HttpResponse res = new Http().send(req);
        return parseClassId(res, 'POST ApexClass');
    }

    private static String patchApexClass(String classId, String body) {
        Map<String, Object> payload = new Map<String, Object>{
            'Body' => body
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(toolingBaseUrl() + '/sobjects/ApexClass/' + classId);
        req.setMethod('PATCH');
        req.setHeader('Authorization', sessionHeader());
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(60000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() == 204) {
            // PATCH returns 204 No Content on success
            return classId;
        }
        throw new ExtoleToolingException(
            'PATCH ApexClass failed: HTTP ' + res.getStatusCode() + ' – ' + res.getBody()
        );
    }

    private static String parseClassId(HttpResponse res, String operation) {
        if (res.getStatusCode() == 201) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String id = (String) result.get('id');
            if (String.isBlank(id)) {
                throw new ExtoleToolingException(operation + ' succeeded but returned no id. Body: ' + res.getBody());
            }
            return id;
        }

        // Translate common errors to human-readable messages
        String errorMsg = translateToolingError(res.getStatusCode(), res.getBody());
        throw new ExtoleToolingException(errorMsg);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Telemetry update (called from generated handler body as a static method)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Updates runtime telemetry fields on the Extole_Event_Cfg__c record
     * corresponding to the given class name. Called by the generated handler after
     * each callout.
     */
    public static void updateConfigTelemetry(
        String className,
        String recordId,
        DateTime attemptedAt,
        Boolean success,
        Integer httpStatus,
        String responseSummary
    ) {
        try {
            List<Extole_Event_Cfg__c> configs = [
                SELECT Id, Config_Key__c,
                       Last_Attempted_At__c, Last_Succeeded_At__c, Last_Failed_At__c,
                       Last_Record_Id__c, Last_HTTP_Status__c, Last_Response_Summary__c
                FROM Extole_Event_Cfg__c
                WHERE Apex_Class_Name__c = :className
                LIMIT 1
            ];
            if (configs.isEmpty()) {
                System.debug('ExtoleToolingService.updateConfigTelemetry: no config found for class ' + className);
                return;
            }
            Extole_Event_Cfg__c cfg = configs[0];

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
            System.debug('ExtoleToolingService.updateConfigTelemetry ERROR: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Error translation
    // ─────────────────────────────────────────────────────────────────────────

    @TestVisible
    static String translateToolingError(Integer statusCode, String body) {
        if (statusCode == 403) {
            return 'The running admin does not have Author Apex permission. Grant "Author Apex" and retry.';
        }
        if (statusCode == 401) {
            return 'Session expired or insufficient privileges. Please log in again and retry.';
        }

        // Try to extract a useful message from the Tooling API error JSON
        try {
            Object raw = JSON.deserializeUntyped(body);
            if (raw instanceof List<Object>) {
                List<Object> errors = (List<Object>) raw;
                if (!errors.isEmpty()) {
                    Map<String, Object> err = (Map<String, Object>) errors[0];
                    String msg = (String) err.get('message');
                    if (!String.isBlank(msg)) {
                        // Apply known-error translations
                        if (msg.contains('does not exist') && msg.contains('field')) {
                            return 'A mapped field does not exist on the selected object: ' + msg;
                        }
                        if (msg.contains('is not queryable')) {
                            return 'A configured field is not queryable in this context: ' + msg;
                        }
                        return 'Apex class deployment failed: ' + msg;
                    }
                }
            }
        } catch (Exception ignore) { }

        return 'Tooling API error HTTP ' + statusCode + ': ' + body;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utility
    // ─────────────────────────────────────────────────────────────────────────

    private static String escapeApexString(String s) {
        if (s == null) return '';
        return s.replace('\\', '\\\\').replace('\'', '\\\'');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Exception type
    // ─────────────────────────────────────────────────────────────────────────

    public class ExtoleToolingException extends Exception {}
}
