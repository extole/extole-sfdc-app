public with sharing class ExtoleEventController {
    private static final List<String> PRIORITY_OBJECTS = new List<String>{
        'Lead',
        'Opportunity',
        'Contact',
        'Account'
    };

    private class SortableObject implements Comparable {
        public String label;
        public String apiName;
        public Boolean isCustom;

        public SortableObject(String label, String apiName, Boolean isCustom) {
            this.label = label;
            this.apiName = apiName;
            this.isCustom = isCustom;
        }

        public Integer compareTo(Object other) {
            SortableObject o = (SortableObject) other;
            if (this.label == null)
                return -1;
            if (o.label == null)
                return 1;
            return this.label.compareTo(o.label);
        }

        public Map<String, Object> toMap() {
            return new Map<String, Object>{
                'label' => label,
                'apiName' => apiName,
                'isCustom' => isCustom
            };
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Extole_Event_Cfg__c> getEventConfigs() {
        return [
            SELECT
                Id,
                Name,
                CreatedDate,
                Config_Key__c,
                Config_Version__c,
                Event_Name__c,
                Trigger_Object__c,
                Trigger_Type__c,
                Trigger_Field__c,
                Trigger_Value__c,
                Trigger_From_Value__c,
                Trigger_To_Value__c,
                Field_Mappings_JSON__c,
                Apex_Class_Name__c,
                Flow_Name__c,
                Status__c,
                Active__c,
                Deploy_Error__c,
                Deploy_Error_Raw__c,
                Last_Deployed__c,
                Deployed_By_User_Id__c,
                Last_Tested_Record_Id__c,
                Last_Attempted_At__c,
                Last_Succeeded_At__c,
                Last_Failed_At__c,
                Last_Record_Id__c,
                Last_HTTP_Status__c,
                Last_Response_Summary__c
            FROM Extole_Event_Cfg__c
            ORDER BY Name ASC
        ];
    }

    @AuraEnabled(cacheable=false)
    public static List<Extole_Event_Log__c> getEventLogs(String configKey) {
        if (String.isBlank(configKey)) {
            return [
                SELECT
                    Id,
                    Name,
                    Config_Key__c,
                    Event_Type__c,
                    User_Id__c,
                    Timestamp__c,
                    Result__c,
                    Detail__c,
                    Sync_Batch_Id__c
                FROM Extole_Event_Log__c
                ORDER BY Timestamp__c DESC
                LIMIT 200
            ];
        }
        return [
            SELECT
                Id,
                Name,
                Config_Key__c,
                Event_Type__c,
                User_Id__c,
                Timestamp__c,
                Result__c,
                Detail__c,
                Sync_Batch_Id__c
            FROM Extole_Event_Log__c
            WHERE Config_Key__c = :configKey
            ORDER BY Timestamp__c DESC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getAvailableObjects() {
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

        Map<String, Map<String, Object>> priorityMap = new Map<String, Map<String, Object>>();
        List<SortableObject> others = new List<SortableObject>();

        for (String apiName : gd.keySet()) {
            Schema.DescribeSObjectResult describe = gd.get(apiName)
                .getDescribe();

            if (!describe.isQueryable() || !describe.isAccessible())
                continue;
            if (describe.isDeprecatedAndHidden())
                continue;

            String objApiName = describe.getName();
            Map<String, Object> objMap = new Map<String, Object>{
                'label' => describe.getLabel(),
                'apiName' => objApiName,
                'isCustom' => describe.isCustom()
            };

            if (PRIORITY_OBJECTS.contains(objApiName)) {
                priorityMap.put(objApiName, objMap);
            } else {
                others.add(
                    new SortableObject(
                        describe.getLabel(),
                        objApiName,
                        describe.isCustom()
                    )
                );
            }
        }

        others.sort();

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

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getFieldsForObject(
        String objectApiName
    ) {
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
            if (!f.isAccessible())
                continue;

            result.add(
                new Map<String, Object>{
                    'label' => f.getLabel(),
                    'apiName' => f.getName(),
                    'type' => String.valueOf(f.getType()),
                    'isRelationship' => false,
                    'relationshipLabel' => null
                }
            );

            if (
                f.getType() == Schema.DisplayType.REFERENCE && !isPolymorphic(f)
            ) {
                String relName = f.getRelationshipName();
                if (!String.isBlank(relName)) {
                    List<Schema.SObjectType> refs = f.getReferenceTo();
                    if (refs != null && refs.size() == 1) {
                        Schema.DescribeSObjectResult relDescribe = refs[0]
                            .getDescribe();
                        if (
                            SKIP_RELATIONSHIP_OBJECTS.contains(
                                relDescribe.getName()
                            )
                        )
                            continue;
                        Map<String, Schema.SObjectField> relFields = relDescribe.fields.getMap();
                        for (String relFieldName : relFields.keySet()) {
                            Schema.DescribeFieldResult rf = relFields.get(
                                    relFieldName
                                )
                                .getDescribe();
                            if (!rf.isAccessible())
                                continue;
                            result.add(
                                new Map<String, Object>{
                                    'label' => relDescribe.getLabel() +
                                    ': ' +
                                    rf.getLabel(),
                                    'apiName' => relName +
                                    '.' +
                                    rf.getName(),
                                    'type' => String.valueOf(rf.getType()),
                                    'isRelationship' => true,
                                    'relationshipLabel' => relDescribe.getLabel()
                                }
                            );
                        }
                    }
                }
            }
        }

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getPicklistValues(
        String objectApiName,
        String fieldApiName
    ) {
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            return new List<Map<String, Object>>();
        }
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        if (sot == null)
            return new List<Map<String, Object>>();
        Schema.SObjectField field = sot.getDescribe()
            .fields.getMap()
            .get(fieldApiName.toLowerCase());
        if (field == null)
            return new List<Map<String, Object>>();
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (
            Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()
        ) {
            if (entry.isActive()) {
                result.add(
                    new Map<String, Object>{
                        'label' => entry.getLabel(),
                        'value' => entry.getValue()
                    }
                );
            }
        }
        return result;
    }

    @AuraEnabled
    public static String previewPayload(String configJson, Id recordId) {
        if (recordId == null || String.isBlank(configJson)) {
            throw new AuraHandledException(
                'configJson and recordId are required'
            );
        }

        Map<String, Object> configMap = (Map<String, Object>) JSON.deserializeUntyped(
            configJson
        );
        String objectApiName = (String) configMap.get('triggerObject');
        String fieldMappingsJSON = (String) configMap.get('fieldMappingsJson');
        String eventName = (String) configMap.get('eventName');

        if (
            String.isBlank(objectApiName) || String.isBlank(fieldMappingsJSON)
        ) {
            throw new AuraHandledException(
                'configJson must include triggerObject and fieldMappingsJson'
            );
        }

        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        if (sot == null) {
            throw new AuraHandledException('Unknown object: ' + objectApiName);
        }
        String safeObjectName = sot.getDescribe().getName();
        Map<String, Schema.SObjectField> fieldMap = sot.getDescribe()
            .fields.getMap();

        List<Object> mappings = (List<Object>) JSON.deserializeUntyped(
            fieldMappingsJSON
        );

        Set<String> fieldsToQuery = new Set<String>{ 'Id' };
        for (Object rawM : mappings) {
            Map<String, Object> m = (Map<String, Object>) rawM;
            String sfdcField = (String) m.get('sfdc_field');
            if (String.isBlank(sfdcField))
                continue;
            if (sfdcField.contains('.')) {
                String[] relParts = sfdcField.split('\\.', 2);
                if (
                    !isValidApiName(relParts[0]) || !isValidApiName(relParts[1])
                )
                    continue;
            } else if (!fieldMap.containsKey(sfdcField.toLowerCase())) {
                continue;
            }
            fieldsToQuery.add(sfdcField);
        }

        String soql =
            'SELECT ' +
            String.join(new List<String>(fieldsToQuery), ', ') +
            ' FROM ' +
            safeObjectName +
            ' WHERE Id = :recordId LIMIT 1';

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
            String sfdcField = (String) m.get('sfdc_field');
            String staticValue = (String) m.get('static_value');
            if (String.isBlank(extoleParam))
                continue;

            if (!String.isBlank(staticValue)) {
                dataMap.put(extoleParam, staticValue);
            } else if (
                !String.isBlank(sfdcField) && fieldsToQuery.contains(sfdcField)
            ) {
                if (sfdcField.contains('.')) {
                    String[] parts = sfdcField.split('\\.', 2);
                    SObject rel = r.getSObject(parts[0]);
                    if (rel != null) {
                        Object value = rel.get(parts[1]);
                        if (value != null)
                            dataMap.put(extoleParam, value);
                    }
                } else {
                    Object value = r.get(sfdcField);
                    if (value != null)
                        dataMap.put(extoleParam, value);
                }
            }
        }

        dataMap.put('app_type', 'extole-sfdc-app');

        Map<String, Object> payload = new Map<String, Object>{
            'event_name' => eventName,
            'data' => dataMap
        };

        return JSON.serializePretty(payload);
    }

    @AuraEnabled
    public static String saveEventConfig(String configJson) {
        Map<String, Object> configMap = (Map<String, Object>) JSON.deserializeUntyped(
            configJson
        );

        String configKey = (String) configMap.get('configKey');
        if (String.isBlank(configKey)) {
            String eventName = (String) configMap.get('eventName');
            String triggerObject = (String) configMap.get('triggerObject');
            if (String.isBlank(eventName) || String.isBlank(triggerObject)) {
                throw new AuraHandledException(
                    'configJson must include configKey or both eventName and triggerObject'
                );
            }
            configKey = (triggerObject +
                '_' +
                eventName)
                .replaceAll('[^a-zA-Z0-9_]', '_');
        }

        Extole_Event_Cfg__c rec = new Extole_Event_Cfg__c(
            Config_Key__c = configKey,
            Event_Name__c = (String) configMap.get('eventName'),
            Trigger_Object__c = (String) configMap.get('triggerObject'),
            Trigger_Type__c = (String) configMap.get('triggerType'),
            Trigger_Field__c = (String) configMap.get('triggerField'),
            Trigger_Value__c = (String) configMap.get('triggerValue'),
            Trigger_From_Value__c = (String) configMap.get('triggerFromValue'),
            Trigger_To_Value__c = (String) configMap.get('triggerToValue'),
            Field_Mappings_JSON__c = (String) configMap.get(
                'fieldMappingsJson'
            ),
            Status__c = 'DRAFT',
            Active__c = false
        );
        try {
            upsert rec Extole_Event_Cfg__c.Config_Key__c;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'Failed to save config: ' + e.getMessage()
            );
        }

        writeEventLog(
            configKey,
            'CONFIG_SAVED',
            'SUCCESS',
            'Draft saved: ' + configKey
        );

        return configKey;
    }

    @AuraEnabled
    public static String suggestUniqueEventName(
        String baseEventName,
        String excludeConfigKey
    ) {
        if (String.isBlank(baseEventName))
            return baseEventName;

        Set<String> existing = new Set<String>();
        String excluded = String.isBlank(excludeConfigKey)
            ? '__none__'
            : excludeConfigKey;
        for (Extole_Event_Cfg__c c : [
            SELECT Event_Name__c
            FROM Extole_Event_Cfg__c
            WHERE Event_Name__c != NULL AND Config_Key__c != :excluded
            LIMIT 500
        ]) {
            existing.add(c.Event_Name__c.toLowerCase());
        }

        if (!existing.contains(baseEventName.toLowerCase()))
            return baseEventName;

        for (Integer i = 2; i <= 99; i++) {
            String candidate = baseEventName + '_' + i;
            if (!existing.contains(candidate.toLowerCase()))
                return candidate;
        }
        return baseEventName;
    }

    @AuraEnabled
    public static String deployEventConfig(String configJson) {
        Map<String, Object> configMap = (Map<String, Object>) JSON.deserializeUntyped(
            configJson
        );
        String configKey = (String) configMap.get('configKey');
        if (String.isBlank(configKey)) {
            String eventName = (String) configMap.get('eventName');
            String triggerObject = (String) configMap.get('triggerObject');
            if (String.isBlank(eventName) || String.isBlank(triggerObject)) {
                throw new AuraHandledException(
                    'configJson must include configKey or both eventName and triggerObject'
                );
            }
            configKey = (triggerObject +
                '_' +
                eventName)
                .replaceAll('[^a-zA-Z0-9_]', '_');
        }

        List<Extole_Event_Cfg__c> configs = [
            SELECT
                Id,
                Config_Key__c,
                Config_Version__c,
                Event_Name__c,
                Trigger_Object__c,
                Trigger_Type__c,
                Trigger_Field__c,
                Trigger_Value__c,
                Field_Mappings_JSON__c,
                Apex_Class_Name__c,
                Flow_Name__c,
                Status__c
            FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = :configKey
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            throw new AuraHandledException(
                'Config not found: ' +
                    configKey +
                    '. Save the config before deploying.'
            );
        }

        Extole_Event_Cfg__c config = configs[0];

        deployEventConfigByKey(config);

        return configKey;
    }

    private static void deployEventConfigByKey(Extole_Event_Cfg__c config) {
        String configKey = config.Config_Key__c;
        String batchId = generateBatchId();

        try {
            Integer newVersion = (config.Config_Version__c == null)
                ? 1
                : (Integer) config.Config_Version__c + 1;

            String expectedFlowName = 'Extole_Flow_' + configKey;
            String oldFlowName = config.Flow_Name__c;
            Boolean oldFlowDeactivated = false;
            Set<String> flowNamesToClean = new Set<String>{ expectedFlowName };
            if (!String.isBlank(oldFlowName))
                flowNamesToClean.add(oldFlowName);
            for (String fn : flowNamesToClean) {
                try {
                    ExtoleMetadataService.deactivateFlow(fn);
                    ExtoleMetadataService.deleteFlow(fn);
                    oldFlowDeactivated = true;
                } catch (Exception e) {
                    System.debug(
                        'deployEventConfig: deactivate/delete flow ' +
                            fn +
                            ' failed (non-fatal): ' +
                            e.getMessage()
                    );
                }
            }

            String flowName = ExtoleMetadataService.deployFlow(
                config.Config_Key__c,
                config.Trigger_Object__c,
                config.Trigger_Type__c,
                config.Trigger_Field__c,
                config.Trigger_Value__c
            );

            config.Apex_Class_Name__c = 'ExtoleUniversalHandler';
            config.Flow_Name__c = flowName;
            config.Status__c = 'ACTIVE';
            config.Active__c = true;
            config.Config_Version__c = newVersion;
            config.Last_Deployed__c = DateTime.now();
            config.Deployed_By_User_Id__c = UserInfo.getUserId();
            config.Deploy_Error__c = '';
            config.Deploy_Error_Raw__c = '';
            update config;

            writeEventLogWithBatch(
                configKey,
                'DEPLOY_INITIATED',
                'SUCCESS',
                'Version ' + newVersion,
                batchId
            );
            if (oldFlowDeactivated) {
                String deactivatedName = String.isBlank(oldFlowName)
                    ? expectedFlowName
                    : oldFlowName;
                writeEventLogWithBatch(
                    configKey,
                    'FLOW_DEACTIVATED',
                    'SUCCESS',
                    'Deactivated: ' + deactivatedName,
                    batchId
                );
            }
            writeEventLogWithBatch(
                configKey,
                'DEPLOY_SUCCEEDED',
                'SUCCESS',
                'Handler: ExtoleUniversalHandler | Flow: ' + flowName,
                batchId
            );
            writeEventLogWithBatch(
                configKey,
                'FLOW_ACTIVATED',
                'SUCCESS',
                'Flow activated: ' + flowName,
                batchId
            );
        } catch (ExtoleMetadataService.ExtoleMetadataException e) {
            String msg = e.getMessage();
            handleDeployFailure(config, msg, msg, batchId);
        } catch (Exception e) {
            String rawMsg = e.getMessage();
            String friendly = 'Unexpected error during deploy: ' + rawMsg;
            handleDeployFailure(config, friendly, rawMsg, batchId);
        }
    }

    @AuraEnabled
    public static void deleteEventConfig(String configKey) {
        List<Extole_Event_Cfg__c> configs = [
            SELECT Id, Config_Key__c, Flow_Name__c, Status__c
            FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = :configKey
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            throw new AuraHandledException(
                'Event config not found: ' + configKey
            );
        }

        Extole_Event_Cfg__c config = configs[0];

        if (!String.isBlank(config.Flow_Name__c)) {
            try {
                ExtoleMetadataService.deactivateFlow(config.Flow_Name__c);
                ExtoleMetadataService.deleteFlow(config.Flow_Name__c);
                writeEventLog(
                    configKey,
                    'FLOW_DEACTIVATED',
                    'SUCCESS',
                    'Deactivated and deleted on config delete: ' +
                    config.Flow_Name__c
                );
            } catch (Exception e) {
                System.debug(
                    'deleteEventConfig: flow deactivation/deletion failed (non-fatal): ' +
                    e.getMessage()
                );
            }
        }

        try {
            delete config;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'Failed to delete config record: ' + e.getMessage()
            );
        }

        writeEventLog(
            configKey,
            'CONFIG_DELETED',
            'SUCCESS',
            'Config deleted. Flow deactivated. Apex class retained as orphan.'
        );
    }

    @AuraEnabled
    public static Map<String, Object> checkEventUsage(String eventName) {
        return ExtoleSafetyCheckService.checkEventUsage(eventName);
    }

    @AuraEnabled
    public static void deactivateEventConfig(String configKey) {
        List<Extole_Event_Cfg__c> configs = [
            SELECT Id, Config_Key__c, Flow_Name__c, Status__c
            FROM Extole_Event_Cfg__c
            WHERE Config_Key__c = :configKey
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            throw new AuraHandledException(
                'Event config not found: ' + configKey
            );
        }

        Extole_Event_Cfg__c config = configs[0];

        if (!String.isBlank(config.Flow_Name__c)) {
            try {
                ExtoleMetadataService.deactivateFlow(config.Flow_Name__c);
            } catch (Exception e) {
                System.debug(
                    'deactivateEventConfig: flow deactivation failed (non-fatal): ' +
                    e.getMessage()
                );
            }
        }

        config.Status__c = 'INACTIVE';
        config.Active__c = false;
        try {
            update config;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'Failed to update config status: ' + e.getMessage()
            );
        }

        writeEventLog(
            configKey,
            'CONFIG_DEACTIVATED',
            'SUCCESS',
            'Config deactivated: ' + configKey
        );
    }

    @AuraEnabled(cacheable=false)
    public static List<Extole_Event_Fire_Log__c> getEventFireLogs() {
        return [
            SELECT
                Id,
                Name,
                Config_Key__c,
                Event_Name__c,
                Record_Id__c,
                Result__c,
                HTTP_Status__c,
                Timestamp__c,
                Detail__c
            FROM Extole_Event_Fire_Log__c
            ORDER BY Timestamp__c DESC
            LIMIT 500
        ];
    }

    @AuraEnabled
    public static Map<String, Integer> clearEventFireLogs() {
        try {
            List<Extole_Event_Fire_Log__c> logs = [
                SELECT Id
                FROM Extole_Event_Fire_Log__c
                LIMIT 10000
            ];
            Integer deletedCount = logs.size();
            if (!logs.isEmpty()) {
                delete logs;
            }
            Integer remainingCount = [
                SELECT COUNT()
                FROM Extole_Event_Fire_Log__c
            ];
            return new Map<String, Integer>{
                'deletedCount' => deletedCount,
                'remainingCount' => remainingCount
            };
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to clear event fire log: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled
    public static Map<String, Integer> clearEventLog() {
        try {
            List<Extole_Event_Log__c> logs = [
                SELECT Id
                FROM Extole_Event_Log__c
                LIMIT 10000
            ];
            Integer deletedCount = logs.size();
            if (!logs.isEmpty()) {
                delete logs;
            }
            Integer remainingCount = [SELECT COUNT() FROM Extole_Event_Log__c];
            return new Map<String, Integer>{
                'deletedCount' => deletedCount,
                'remainingCount' => remainingCount
            };
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to clear event log: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled
    public static Map<String, Object> pollDeployStatus(String jobId) {
        Map<String, Object> result = new Map<String, Object>{
            'status' => 'PENDING',
            'errorMessage' => null
        };

        if (String.isBlank(jobId)) {
            result.put('status', 'FAILED');
            result.put('errorMessage', 'No jobId provided');
            return result;
        }

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

        Extole_Event_Cfg__c config = configs[0];
        if (config.Status__c == 'ACTIVE') {
            result.put('status', 'SUCCEEDED');
        } else if (config.Status__c == 'DEPLOY_FAILED') {
            result.put('status', 'FAILED');
            result.put('errorMessage', config.Deploy_Error__c);
        } else {
            result.put('status', 'PENDING');
        }

        return result;
    }

    private static void handleDeployFailure(
        Extole_Event_Cfg__c config,
        String friendlyMsg,
        String rawMsg,
        String batchId
    ) {
        config.Status__c = 'DEPLOY_FAILED';
        config.Active__c = false;
        config.Deploy_Error__c = truncate(friendlyMsg, 1300);
        config.Deploy_Error_Raw__c = truncate(rawMsg, 1300);
        try {
            if (config.Id != null)
                update config;
        } catch (Exception ignored) {
        }

        writeEventLogWithBatch(
            config.Config_Key__c,
            'DEPLOY_FAILED',
            'FAILED',
            truncate(friendlyMsg, 1000),
            batchId
        );
    }

    private static void writeEventLog(
        String configKey,
        String eventType,
        String result,
        String detail
    ) {
        writeEventLogWithBatch(configKey, eventType, result, detail, null);
    }

    private static void writeEventLogWithBatch(
        String configKey,
        String eventType,
        String result,
        String detail,
        String batchId
    ) {
        try {
            insert new Extole_Event_Log__c(
                Config_Key__c = configKey,
                Event_Type__c = eventType,
                User_Id__c = UserInfo.getUserId(),
                Timestamp__c = DateTime.now(),
                Result__c = result,
                Detail__c = detail,
                Sync_Batch_Id__c = batchId
            );
        } catch (Exception e) {
            System.debug(
                'ExtoleEventController.writeEventLog: failed ' + e.getMessage()
            );
        }
    }

    private static String generateBatchId() {
        return 'deploy-' +
            DateTime.now().getTime() +
            '-' +
            UserInfo.getUserId().left(8);
    }

    private static String truncate(String s, Integer maxLen) {
        if (s == null)
            return '';
        return s.length() > maxLen ? s.substring(0, maxLen) : s;
    }

    private static Boolean isValidApiName(String name) {
        return String.isNotBlank(name) &&
            Pattern.matches('^[a-zA-Z][a-zA-Z0-9_]*$', name);
    }

    private static final Set<String> SKIP_RELATIONSHIP_OBJECTS = new Set<String>{
        'User',
        'Profile',
        'RecordType',
        'Group',
        'Queue',
        'BusinessHours',
        'Organization',
        'Division',
        'UserRole',
        'Territory',
        'Territory2'
    };

    private static Boolean isPolymorphic(Schema.DescribeFieldResult f) {
        return f.getReferenceTo() != null && f.getReferenceTo().size() > 1;
    }
}
