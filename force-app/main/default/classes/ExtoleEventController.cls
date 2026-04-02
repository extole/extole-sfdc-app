/**
 * ExtoleEventController
 *
 * @AuraEnabled controller for the Event Configurator LWC tab.
 * All data access, deploy orchestration, and maintenance operations for the
 * configurator go through this class — LWC components call nothing else.
 *
 * Logging: every meaningful action is written to Extole_Event_Log__c.
 */
public with sharing class ExtoleEventController {

    // Common objects that appear at the top of the object picker
    private static final List<String> PRIORITY_OBJECTS = new List<String>{
        'Lead', 'Opportunity', 'Contact', 'Account'
    };

    // ─────────────────────────────────────────────────────────────────────────
    // Sortable wrapper for object picker (Comparable on label)
    // ─────────────────────────────────────────────────────────────────────────

    private class SortableObject implements Comparable {
        public String label;
        public String apiName;
        public Boolean isCustom;

        public SortableObject(String label, String apiName, Boolean isCustom) {
            this.label    = label;
            this.apiName  = apiName;
            this.isCustom = isCustom;
        }

        public Integer compareTo(Object other) {
            SortableObject o = (SortableObject) other;
            if (this.label == null) return -1;
            if (o.label == null) return 1;
            return this.label.compareTo(o.label);
        }

        public Map<String, Object> toMap() {
            return new Map<String, Object>{
                'label'    => label,
                'apiName'  => apiName,
                'isCustom' => isCustom
            };
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Event Config reads
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Return all Extole_Event_Cfg__c records.
     * Includes all runtime telemetry and state fields needed by the list view.
     */
    @AuraEnabled(cacheable=false)
    public static List<Extole_Event_Cfg__c> getEventConfigs() {
        return [
            SELECT Id, Name, CreatedDate,
                   Config_Key__c, Config_Version__c, Event_Name__c,
                   Trigger_Object__c, Trigger_Type__c, Trigger_Field__c,
                   Trigger_Value__c, Trigger_From_Value__c, Trigger_To_Value__c,
                   Field_Mappings_JSON__c, Apex_Class_Name__c, Flow_Name__c,
                   Status__c, Active__c,
                   Deploy_Error__c, Deploy_Error_Raw__c,
                   Last_Deployed__c, Deployed_By_User_Id__c, Last_Tested_Record_Id__c,
                   Last_Attempted_At__c, Last_Succeeded_At__c, Last_Failed_At__c,
                   Last_Record_Id__c, Last_HTTP_Status__c, Last_Response_Summary__c
            FROM Extole_Event_Cfg__c
            ORDER BY Name ASC
        ];
    }

    /**
     * Return recent Extole_Event_Log__c entries for a given config key.
     * Returns up to 200 entries in reverse-chronological order.
     */
    @AuraEnabled(cacheable=false)
    public static List<Extole_Event_Log__c> getEventLogs(String configKey) {
        if (String.isBlank(configKey)) {
            return [
                SELECT Id, Name, Config_Key__c, Event_Type__c, User_Id__c,
                       Timestamp__c, Result__c, Detail__c, Sync_Batch_Id__c
                FROM Extole_Event_Log__c
                ORDER BY Timestamp__c DESC
                LIMIT 200
            ];
        }
        return [
            SELECT Id, Name, Config_Key__c, Event_Type__c, User_Id__c,
                   Timestamp__c, Result__c, Detail__c, Sync_Batch_Id__c
            FROM Extole_Event_Log__c
            WHERE Config_Key__c = :configKey
            ORDER BY Timestamp__c DESC
            LIMIT 200
        ];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Schema inspection
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Enumerate all org objects.
     * Returns a list of { label, apiName, isCustom } maps.
     * Common objects (Lead, Opportunity, Contact, Account) are surfaced first.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getAvailableObjects() {
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

        // Separate priority objects from the rest
        Map<String, Map<String, Object>> priorityMap = new Map<String, Map<String, Object>>();
        List<SortableObject> others = new List<SortableObject>();

        for (String apiName : gd.keySet()) {
            Schema.DescribeSObjectResult describe = gd.get(apiName).getDescribe();

            // Skip non-queryable, non-accessible, and internal objects
            if (!describe.isQueryable() || !describe.isAccessible()) continue;
            if (describe.isDeprecatedAndHidden()) continue;

            String objApiName = describe.getName();
            Map<String, Object> objMap = new Map<String, Object>{
                'label'    => describe.getLabel(),
                'apiName'  => objApiName,
                'isCustom' => describe.isCustom()
            };

            if (PRIORITY_OBJECTS.contains(objApiName)) {
                priorityMap.put(objApiName, objMap);
            } else {
                others.add(new SortableObject(describe.getLabel(), objApiName, describe.isCustom()));
            }
        }

        // Sort non-priority objects alphabetically by label
        others.sort();

        // Build result: priority first (in defined order), then alphabetical rest
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (String priorityName : PRIORITY_OBJECTS) {
            if (priorityMap.containsKey(priorityName)) {
                result.add(priorityMap.get(priorityName));
            }
        }
        for (SortableObject so : others) {
            result.add(so.toMap());
        }
        return result;
    }

    /**
     * Return all queryable fields for the given object, plus one-hop lookup fields.
     * Excludes polymorphic relationships per spec.
     *
     * Return shape per field: { label, apiName, type, isRelationship, relationshipLabel }
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getFieldsForObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('objectApiName is required');
        }

        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        if (sot == null) {
            throw new AuraHandledException('Unknown object: ' + objectApiName);
        }

        Schema.DescribeSObjectResult describe = sot.getDescribe();
        Map<String, Schema.SObjectField> fields = describe.fields.getMap();

        List<Map<String, Object>> result = new List<Map<String, Object>>();

        for (String fieldName : fields.keySet()) {
            Schema.DescribeFieldResult f = fields.get(fieldName).getDescribe();
            if (!f.isAccessible()) continue;

            result.add(new Map<String, Object>{
                'label'             => f.getLabel(),
                'apiName'           => f.getName(),
                'type'              => String.valueOf(f.getType()),
                'isRelationship'    => false,
                'relationshipLabel' => null
            });

            // One-hop lookup / master-detail fields — non-polymorphic only
            if (f.getType() == Schema.DisplayType.REFERENCE && !isPolymorphic(f)) {
                String relName = f.getRelationshipName();
                if (!String.isBlank(relName)) {
                    List<Schema.SObjectType> refs = f.getReferenceTo();
                    if (refs != null && refs.size() == 1) {
                        Schema.DescribeSObjectResult relDescribe = refs[0].getDescribe();
                        if (SKIP_RELATIONSHIP_OBJECTS.contains(relDescribe.getName())) continue;
                        Map<String, Schema.SObjectField> relFields = relDescribe.fields.getMap();
                        for (String relFieldName : relFields.keySet()) {
                            Schema.DescribeFieldResult rf = relFields.get(relFieldName).getDescribe();
                            if (!rf.isAccessible()) continue;
                            result.add(new Map<String, Object>{
                                'label'             => relDescribe.getLabel() + ': ' + rf.getLabel(),
                                'apiName'           => relName + '.' + rf.getName(),
                                'type'              => String.valueOf(rf.getType()),
                                'isRelationship'    => true,
                                'relationshipLabel' => relDescribe.getLabel()
                            });
                        }
                    }
                }
            }
        }

        return result;
    }

    /**
     * Returns active picklist values for a given object field.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getPicklistValues(String objectApiName, String fieldApiName) {
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            return new List<Map<String, Object>>();
        }
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        if (sot == null) return new List<Map<String, Object>>();
        Schema.SObjectField field = sot.getDescribe().fields.getMap().get(fieldApiName.toLowerCase());
        if (field == null) return new List<Map<String, Object>>();
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                result.add(new Map<String, Object>{ 'label' => entry.getLabel(), 'value' => entry.getValue() });
            }
        }
        return result;
    }

    /**
     * Build a preview JSON payload for a real record without sending it.
     * Queries the record, applies the field mappings, and returns the payload string.
     *
     * Accepts configJson (a serialized config object from the LWC) and recordId.
     * configJson must contain: triggerObject, fieldMappingsJson, eventName.
     */
    @AuraEnabled
    public static String previewPayload(String configJson, Id recordId) {
        if (recordId == null || String.isBlank(configJson)) {
            throw new AuraHandledException('configJson and recordId are required');
        }

        Map<String, Object> configMap = (Map<String, Object>) JSON.deserializeUntyped(configJson);
        String objectApiName   = (String) configMap.get('triggerObject');
        String fieldMappingsJSON = (String) configMap.get('fieldMappingsJson');
        String eventName       = (String) configMap.get('eventName');

        if (String.isBlank(objectApiName) || String.isBlank(fieldMappingsJSON)) {
            throw new AuraHandledException('configJson must include triggerObject and fieldMappingsJson');
        }

        // Validate objectApiName against Schema before interpolating into SOQL
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        if (sot == null) {
            throw new AuraHandledException('Unknown object: ' + objectApiName);
        }
        String safeObjectName = sot.getDescribe().getName();
        Map<String, Schema.SObjectField> fieldMap = sot.getDescribe().fields.getMap();

        List<Object> mappings = (List<Object>) JSON.deserializeUntyped(fieldMappingsJSON);

        // Build the field set to SOQL-query — validate each field against Schema
        Set<String> fieldsToQuery = new Set<String>{ 'Id' };
        for (Object rawM : mappings) {
            Map<String, Object> m = (Map<String, Object>) rawM;
            String sfdcField = (String) m.get('sfdc_field');
            if (String.isBlank(sfdcField)) continue;
            // For dot-notation (e.g. Account.Name), validate the base relationship field
            String baseField = sfdcField.contains('.')
                ? sfdcField.split('\\.', 2)[0].toLowerCase()
                : sfdcField.toLowerCase();
            if (!fieldMap.containsKey(baseField)) continue;
            fieldsToQuery.add(sfdcField);
        }

        String soql = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ')
            + ' FROM ' + safeObjectName + ' WHERE Id = :recordId LIMIT 1';

        List<SObject> records;
        try {
            records = Database.query(soql);
        } catch (QueryException e) {
            throw new AuraHandledException('Query failed: ' + e.getMessage());
        }

        if (records.isEmpty()) {
            throw new AuraHandledException('Record not found: ' + recordId);
        }

        SObject r = records[0];
        Map<String, Object> dataMap = new Map<String, Object>();

        for (Object rawM : mappings) {
            Map<String, Object> m = (Map<String, Object>) rawM;
            String extoleParam = (String) m.get('extole_param');
            String sfdcField   = (String) m.get('sfdc_field');
            String staticValue = (String) m.get('static_value');
            if (String.isBlank(extoleParam)) continue;

            if (!String.isBlank(staticValue)) {
                dataMap.put(extoleParam, staticValue);
            } else if (!String.isBlank(sfdcField) && fieldsToQuery.contains(sfdcField)) {
                // Only access fields that passed Schema validation (were added to fieldsToQuery)
                if (sfdcField.contains('.')) {
                    String[] parts = sfdcField.split('\\.', 2);
                    SObject rel = r.getSObject(parts[0]);
                    if (rel != null) {
                        Object val = rel.get(parts[1]);
                        if (val != null) dataMap.put(extoleParam, val);
                    }
                } else {
                    Object val = r.get(sfdcField);
                    if (val != null) dataMap.put(extoleParam, val);
                }
            }
        }

        dataMap.put('app_type', 'salesforce_crm');

        Map<String, Object> payload = new Map<String, Object>{
            'event_name' => eventName,
            'data'       => dataMap
        };

        return JSON.serializePretty(payload);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Config save (upsert via Metadata API)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Save (create or update) an Extole_Event_Cfg__c record as DRAFT.
     * Called when the user advances from step 2 to step 3 in the wizard,
     * so the config is persisted before deploy and appears in the list.
     *
     * Accepts the same configJson format as deployEventConfig.
     * Returns the configKey so the LWC can pass it on deploy.
     */
    @AuraEnabled
    public static String saveEventConfig(String configJson) {
        Map<String, Object> configMap = (Map<String, Object>) JSON.deserializeUntyped(configJson);

        String configKey = (String) configMap.get('configKey');
        if (String.isBlank(configKey)) {
            String eventName    = (String) configMap.get('eventName');
            String triggerObject = (String) configMap.get('triggerObject');
            if (String.isBlank(eventName) || String.isBlank(triggerObject)) {
                throw new AuraHandledException('configJson must include configKey or both eventName and triggerObject');
            }
            configKey = (triggerObject + '_' + eventName).replaceAll('[^a-zA-Z0-9_]', '_');
        }

        Extole_Event_Cfg__c rec = new Extole_Event_Cfg__c(
            Config_Key__c          = configKey,
            Event_Name__c          = (String) configMap.get('eventName'),
            Trigger_Object__c      = (String) configMap.get('triggerObject'),
            Trigger_Type__c        = (String) configMap.get('triggerType'),
            Trigger_Field__c       = (String) configMap.get('triggerField'),
            Trigger_Value__c       = (String) configMap.get('triggerValue'),
            Trigger_From_Value__c  = (String) configMap.get('triggerFromValue'),
            Trigger_To_Value__c    = (String) configMap.get('triggerToValue'),
            Field_Mappings_JSON__c = (String) configMap.get('fieldMappingsJson'),
            Status__c              = 'DRAFT',
            Active__c              = false
        );
        try {
            upsert rec Extole_Event_Cfg__c.Config_Key__c;
        } catch (DmlException e) {
            throw new AuraHandledException('Failed to save config: ' + e.getMessage());
        }

        writeEventLog(configKey, 'CONFIG_SAVED', 'SUCCESS', 'Draft saved: ' + configKey);

        return configKey;
    }

    /**
     * Returns the first available event name derived from baseEventName.
     * If baseEventName is taken, tries baseEventName_2, _3, etc.
     * Excludes the current config (excludeConfigKey) from the uniqueness check
     * so editing an existing config does not flag itself as a duplicate.
     */
    @AuraEnabled
    public static String suggestUniqueEventName(String baseEventName, String excludeConfigKey) {
        if (String.isBlank(baseEventName)) return baseEventName;

        Set<String> existing = new Set<String>();
        String excluded = String.isBlank(excludeConfigKey) ? '__none__' : excludeConfigKey;
        for (Extole_Event_Cfg__c c : [
            SELECT Event_Name__c FROM Extole_Event_Cfg__c
            WHERE Event_Name__c != null AND Config_Key__c != :excluded
            LIMIT 500
        ]) {
            existing.add(c.Event_Name__c.toLowerCase());
        }

        if (!existing.contains(baseEventName.toLowerCase())) return baseEventName;

        for (Integer i = 2; i <= 99; i++) {
            String candidate = baseEventName + '_' + i;
            if (!existing.contains(candidate.toLowerCase())) return candidate;
        }
        return baseEventName;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Deploy orchestration
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Full deploy sequence for a config:
     * 1. Load the saved config record
     * 2. Deactivate old Flow (if it exists)
     * 3. Deploy updated Flow via Metadata API (calls ExtoleUniversalHandler at runtime)
     * 4. Update record: Apex_Class_Name__c, Flow_Name__c, Status__c=ACTIVE, Last_Deployed__c
     *
     * Callouts use the Extole_Tooling Named Credential — no session token in JS.
     *
     * @param configJson  Full config JSON from the LWC wizard
     * @return String jobId (=configKey, for use with pollDeployStatus)
     */
    @AuraEnabled
    public static String deployEventConfig(String configJson) {
        // Step 1: Parse the configJson and determine the configKey
        Map<String, Object> configMap = (Map<String, Object>) JSON.deserializeUntyped(configJson);
        String configKey = (String) configMap.get('configKey');
        if (String.isBlank(configKey)) {
            // Generate a key from eventName + triggerObject
            String eventName = (String) configMap.get('eventName');
            String triggerObject = (String) configMap.get('triggerObject');
            if (String.isBlank(eventName) || String.isBlank(triggerObject)) {
                throw new AuraHandledException('configJson must include configKey or both eventName and triggerObject');
            }
            configKey = (triggerObject + '_' + eventName).replaceAll('[^a-zA-Z0-9_]', '_');
        }

        // Step 2: Load saved config — saveEventConfig must be called before deployEventConfig
        List<Extole_Event_Cfg__c> configs = [
            SELECT Id, Config_Key__c, Config_Version__c,
                   Event_Name__c, Trigger_Object__c, Trigger_Type__c,
                   Trigger_Field__c, Trigger_Value__c,
                   Field_Mappings_JSON__c, Apex_Class_Name__c, Flow_Name__c,
                   Status__c
            FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = :configKey
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            throw new AuraHandledException('Config not found: ' + configKey + '. Save the config before deploying.');
        }

        Extole_Event_Cfg__c cfg = configs[0];

        deployEventConfigByKey(cfg);

        // Return the configKey as the jobId for polling
        return configKey;
    }

    /**
     * Internal deploy sequence given a loaded Extole_Event_Cfg__c record.
     */
    private static void deployEventConfigByKey(Extole_Event_Cfg__c cfg) {
        String configKey = cfg.Config_Key__c;
        String batchId = generateBatchId();

        try {
            // ── CALLOUTS PHASE ────────────────────────────────────────────
            // No DML may occur before or between callouts.

            Integer newVersion = (cfg.Config_Version__c == null)
                ? 1 : (Integer) cfg.Config_Version__c + 1;

            // Callout 1: Deactivate then delete old Flow versions (non-fatal).
            // Always attempt the expected flow name (derived from configKey) in addition
            // to the stored Flow_Name__c, so stale flows from prior failed deploys are
            // cleaned up even when Flow_Name__c was never set.
            String expectedFlowName = 'Extole_Flow_' + configKey;
            String oldFlowName = cfg.Flow_Name__c;
            Boolean oldFlowDeactivated = false;
            Set<String> flowNamesToClean = new Set<String>{ expectedFlowName };
            if (!String.isBlank(oldFlowName)) flowNamesToClean.add(oldFlowName);
            for (String fn : flowNamesToClean) {
                try {
                    ExtoleMetadataService.deactivateFlow(fn);
                    ExtoleMetadataService.deleteFlow(fn);
                    oldFlowDeactivated = true;
                } catch (Exception e) {
                    System.debug('deployEventConfig: deactivate/delete flow ' + fn + ' failed (non-fatal): ' + e.getMessage());
                }
            }

            // Callout 2: Deploy new Flow (invokes ExtoleUniversalHandler at runtime)
            String flowName = ExtoleMetadataService.deployFlow(
                cfg.Config_Key__c,
                cfg.Trigger_Object__c,
                cfg.Trigger_Type__c,
                cfg.Trigger_Field__c,
                cfg.Trigger_Value__c
            );

            // ── DML PHASE ─────────────────────────────────────────────────
            // All callouts are complete — DML is now safe.

            cfg.Apex_Class_Name__c     = 'ExtoleUniversalHandler';
            cfg.Flow_Name__c           = flowName;
            cfg.Status__c              = 'ACTIVE';
            cfg.Active__c              = true;
            cfg.Config_Version__c      = newVersion;
            cfg.Last_Deployed__c       = DateTime.now();
            cfg.Deployed_By_User_Id__c = UserInfo.getUserId();
            cfg.Deploy_Error__c        = '';
            cfg.Deploy_Error_Raw__c    = '';
            update cfg;

            writeEventLogWithBatch(configKey, 'DEPLOY_INITIATED',
                'SUCCESS', 'Version ' + newVersion, batchId);
            if (oldFlowDeactivated) {
                String deactivatedName = String.isBlank(oldFlowName) ? expectedFlowName : oldFlowName;
                writeEventLogWithBatch(configKey, 'FLOW_DEACTIVATED',
                    'SUCCESS', 'Deactivated: ' + deactivatedName, batchId);
            }
            writeEventLogWithBatch(configKey, 'DEPLOY_SUCCEEDED',
                'SUCCESS', 'Handler: ExtoleUniversalHandler | Flow: ' + flowName, batchId);
            writeEventLogWithBatch(configKey, 'FLOW_ACTIVATED',
                'SUCCESS', 'Flow activated: ' + flowName, batchId);

        } catch (ExtoleMetadataService.ExtoleMetadataException e) {
            String msg = e.getMessage();
            handleDeployFailure(cfg, msg, msg, batchId);
        } catch (Exception e) {
            String rawMsg   = e.getMessage();
            String friendly = 'Unexpected error during deploy: ' + rawMsg;
            handleDeployFailure(cfg, friendly, rawMsg, batchId);
        }
    }

    /**
     * Delete a config: deactivate flow, retain Apex class as orphan, delete record.
     *
     * @param configKey  Config_Key__c of the record
     */
    @AuraEnabled
    public static void deleteEventConfig(String configKey) {
        List<Extole_Event_Cfg__c> configs = [
            SELECT Id, Config_Key__c, Flow_Name__c, Status__c
            FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = :configKey
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            throw new AuraHandledException('Event config not found: ' + configKey);
        }

        Extole_Event_Cfg__c cfg = configs[0];

        // Deactivate the Flow (retain as orphan per spec)
        if (!String.isBlank(cfg.Flow_Name__c)) {
            try {
                ExtoleMetadataService.deactivateFlow(cfg.Flow_Name__c);
                writeEventLog(configKey, 'FLOW_DEACTIVATED', 'SUCCESS',
                    'Deactivated on config delete: ' + cfg.Flow_Name__c);
            } catch (Exception e) {
                System.debug('deleteEventConfig: flow deactivation failed (non-fatal): ' + e.getMessage());
            }
        }

        try {
            delete cfg;
        } catch (DmlException e) {
            throw new AuraHandledException('Failed to delete config record: ' + e.getMessage());
        }

        writeEventLog(configKey, 'CONFIG_DELETED', 'SUCCESS',
            'Config deleted. Flow deactivated. Apex class retained as orphan.');
    }

    @AuraEnabled
    public static Map<String, Object> checkEventUsage(String eventName) {
        return ExtoleSafetyCheckService.checkEventUsage(eventName);
    }

    /**
     * Deactivate (set INACTIVE) a config without deleting it.
     * Deactivates the associated Flow and writes a log entry.
     *
     * @param configKey  Config_Key__c of the record
     */
    @AuraEnabled
    public static void deactivateEventConfig(String configKey) {
        List<Extole_Event_Cfg__c> configs = [
            SELECT Id, Config_Key__c, Flow_Name__c, Status__c
            FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = :configKey
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            throw new AuraHandledException('Event config not found: ' + configKey);
        }

        Extole_Event_Cfg__c cfg = configs[0];

        // Deactivate the Flow
        if (!String.isBlank(cfg.Flow_Name__c)) {
            try {
                ExtoleMetadataService.deactivateFlow(cfg.Flow_Name__c);
            } catch (Exception e) {
                System.debug('deactivateEventConfig: flow deactivation failed (non-fatal): ' + e.getMessage());
            }
        }

        cfg.Status__c = 'INACTIVE';
        cfg.Active__c = false;
        try {
            update cfg;
        } catch (DmlException e) {
            throw new AuraHandledException('Failed to update config status: ' + e.getMessage());
        }

        writeEventLog(configKey, 'CONFIG_DEACTIVATED', 'SUCCESS',
            'Config deactivated: ' + configKey);
    }

    /**
     * Delete all Extole_Event_Log__c records in the org.
     * Used by the "Clear Event Log" button in the Event Configurator.
     */
    @AuraEnabled
    public static void clearEventLog() {
        try {
            List<Extole_Event_Log__c> logs = [SELECT Id FROM Extole_Event_Log__c LIMIT 10000];
            if (!logs.isEmpty()) {
                delete logs;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Failed to clear event log: ' + e.getMessage());
        }
    }

    /**
     * Returns the current deploy status for a config.
     * deployEventConfig is synchronous, so by the time the LWC calls this,
     * the deploy is already complete. Looks up the config record status as the source of truth.
     *
     * @param jobId  The configKey returned by deployEventConfig
     * @return Map with status (PENDING | SUCCEEDED | FAILED) and errorMessage
     */
    @AuraEnabled
    public static Map<String, Object> pollDeployStatus(String jobId) {
        Map<String, Object> result = new Map<String, Object>{
            'status'       => 'PENDING',
            'errorMessage' => null
        };

        if (String.isBlank(jobId)) {
            result.put('status', 'FAILED');
            result.put('errorMessage', 'No jobId provided');
            return result;
        }

        // deployEventConfig is synchronous — by the time pollDeployStatus is called,
        // the deploy is already complete. Look up the record status as proxy.
        List<Extole_Event_Cfg__c> configs = [
            SELECT Status__c, Deploy_Error__c
            FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = :jobId
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            result.put('status', 'FAILED');
            result.put('errorMessage', 'Config not found: ' + jobId);
            return result;
        }

        Extole_Event_Cfg__c cfg = configs[0];
        if (cfg.Status__c == 'ACTIVE') {
            result.put('status', 'SUCCEEDED');
        } else if (cfg.Status__c == 'DEPLOY_FAILED') {
            result.put('status', 'FAILED');
            result.put('errorMessage', cfg.Deploy_Error__c);
        } else {
            // DRAFT / INACTIVE — treat as still pending
            result.put('status', 'PENDING');
        }

        return result;
    }

    // clearOrphanedHandlers() was removed — per-config handler classes no longer exist.
    // The universal handler (ExtoleUniversalHandler) is a static class; there is nothing to clean up.

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Mark config as DEPLOY_FAILED and log the error.
     */
    private static void handleDeployFailure(
        Extole_Event_Cfg__c cfg,
        String friendlyMsg,
        String rawMsg,
        String batchId
    ) {
        cfg.Status__c          = 'DEPLOY_FAILED';
        cfg.Active__c          = false;
        cfg.Deploy_Error__c    = truncate(friendlyMsg, 1300);
        cfg.Deploy_Error_Raw__c = truncate(rawMsg, 1300);
        try {
            if (cfg.Id != null) update cfg;
        } catch (Exception ignored) { }

        writeEventLogWithBatch(cfg.Config_Key__c, 'DEPLOY_FAILED',
            'FAILED', truncate(friendlyMsg, 1000), batchId);
    }

    private static void writeEventLog(
        String configKey, String eventType, String result, String detail
    ) {
        writeEventLogWithBatch(configKey, eventType, result, detail, null);
    }

    private static void writeEventLogWithBatch(
        String configKey, String eventType, String result, String detail, String batchId
    ) {
        try {
            insert new Extole_Event_Log__c(
                Config_Key__c    = configKey,
                Event_Type__c    = eventType,
                User_Id__c       = UserInfo.getUserId(),
                Timestamp__c     = DateTime.now(),
                Result__c        = result,
                Detail__c        = detail,
                Sync_Batch_Id__c = batchId
            );
        } catch (Exception e) {
            System.debug('ExtoleEventController.writeEventLog: failed ' + e.getMessage());
        }
    }

    private static String generateBatchId() {
        return 'deploy-' + DateTime.now().getTime() + '-' + UserInfo.getUserId().left(8);
    }

    private static String truncate(String s, Integer maxLen) {
        if (s == null) return '';
        return s.length() > maxLen ? s.substring(0, maxLen) : s;
    }

    // Infrastructure/system objects excluded from one-hop relationship traversal
    private static final Set<String> SKIP_RELATIONSHIP_OBJECTS = new Set<String>{
        'User', 'Profile', 'RecordType', 'Group', 'Queue', 'BusinessHours',
        'Organization', 'Division', 'UserRole', 'Territory', 'Territory2'
    };

    /**
     * Returns true for polymorphic reference fields (e.g. Task.WhoId, Task.WhatId).
     * Polymorphic = can reference more than one object type.
     */
    private static Boolean isPolymorphic(Schema.DescribeFieldResult f) {
        return f.getReferenceTo() != null && f.getReferenceTo().size() > 1;
    }
}
