/**
 * ExtoleMetadataService
 *
 * Deploys, deactivates, and deletes Record-Triggered Flows via the Salesforce
 * Tooling API. All callouts use the Extole_Tooling Named Credential — no
 * session token is required in the calling context.
 *
 * Auth: Named Credential 'Extole_Tooling' (OAuth 2.0, NamedUser principal).
 * Run scripts/setup_named_credential.sh once per org to configure it.
 * Required permission: "Customize Application".
 */
public with sharing class ExtoleMetadataService {

    private static final String API_VERSION = '59.0';

    // All Tooling API paths are relative to the Named Credential endpoint,
    // which is: https://<orgDomain>/services/data/v59.0/tooling
    private static final String NC_BASE = 'callout:Extole_Tooling';

    // ─────────────────────────────────────────────────────────────────────────
    // Flow deployment
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Generate and deploy a Record-Triggered Flow that calls ExtoleUniversalHandler.
     *
     * @param configKey      Stable config key (used in flow name; passed to handler at runtime)
     * @param triggerObject  SFDC object API name (e.g. 'Lead')
     * @param triggerType    One of: CREATED, UPDATED, FIELD_EQUALS, FIELD_CHANGES
     * @param triggerField   Field API name (for FIELD_EQUALS / FIELD_CHANGES)
     * @param triggerValue   Value to match (for FIELD_EQUALS)
     * @return Flow developer name that was deployed
     */
    public static String deployFlow(
        String configKey,
        String triggerObject,
        String triggerType,
        String triggerField,
        String triggerValue
    ) {
        String flowName = 'Extole_Flow_' + configKey;
        Map<String, Object> metadata = buildFlowMetadata(
            flowName, configKey, triggerObject, triggerType, triggerField, triggerValue
        );

        Map<String, Object> payload = new Map<String, Object>{
            'FullName' => flowName,
            'Metadata' => metadata
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NC_BASE + '/sobjects/Flow/');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(60000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 201) {
            throw new ExtoleMetadataException(
                translateMetadataError(res.getStatusCode(), res.getBody())
            );
        }

        System.debug('ExtoleMetadataService.deployFlow: deployed ' + flowName);
        return flowName;
    }

    /**
     * Deactivate a Flow by setting its FlowDefinition activeVersionNumber to 0.
     * Must be called before deploying a new version of the same flow.
     *
     * @param flowName  Flow developer name
     */
    public static void deactivateFlow(String flowName) {
        String defId = queryFlowDefinitionId(flowName);
        if (defId == null) {
            System.debug('ExtoleMetadataService.deactivateFlow: no FlowDefinition found for ' + flowName);
            return;
        }

        Map<String, Object> payload = new Map<String, Object>{
            'Metadata' => new Map<String, Object>{
                'activeVersionNumber' => 0
            }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NC_BASE + '/sobjects/FlowDefinition/' + defId);
        req.setMethod('PATCH');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(60000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 204) {
            // Non-fatal — log and continue (flow may already be inactive)
            System.debug('ExtoleMetadataService.deactivateFlow: PATCH returned '
                + res.getStatusCode() + ' – ' + res.getBody());
        } else {
            System.debug('ExtoleMetadataService.deactivateFlow: deactivated ' + flowName);
        }
    }

    /**
     * Delete all versions of a Flow by DeveloperName.
     *
     * @param flowName  Flow developer name
     */
    public static void deleteFlow(String flowName) {
        List<String> flowIds = queryFlowVersionIds(flowName);
        if (flowIds.isEmpty()) {
            System.debug('ExtoleMetadataService.deleteFlow: no Flow versions found for ' + flowName);
            return;
        }
        for (String flowId : flowIds) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NC_BASE + '/sobjects/Flow/' + flowId);
            req.setMethod('DELETE');
            req.setTimeout(30000);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 204) {
                System.debug('ExtoleMetadataService.deleteFlow: DELETE ' + flowId
                    + ' returned ' + res.getStatusCode() + ' – ' + res.getBody());
            }
        }
        System.debug('ExtoleMetadataService.deleteFlow: deleted ' + flowIds.size()
            + ' version(s) of ' + flowName);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Flow metadata JSON generation
    // ─────────────────────────────────────────────────────────────────────────

    @TestVisible
    static Map<String, Object> buildFlowMetadata(
        String flowName,
        String configKey,
        String triggerObject,
        String triggerType,
        String triggerField,
        String triggerValue
    ) {
        String recordTriggerType;
        if (triggerType == 'CREATED') {
            recordTriggerType = 'Create';
        } else {
            recordTriggerType = 'CreateAndUpdate';
        }

        Map<String, Object> startNode = new Map<String, Object>{
            'locationX'         => 50,
            'locationY'         => 50,
            'connector'         => new Map<String, Object>{ 'targetReference' => 'InvokeHandler' },
            'object'            => triggerObject,
            'recordTriggerType' => recordTriggerType,
            'triggerType'       => 'RecordAfterSave'
        };

        // Add entry condition filter for FIELD_EQUALS and FIELD_CHANGES
        if (triggerType == 'FIELD_EQUALS'
            && !String.isBlank(triggerField)
            && !String.isBlank(triggerValue))
        {
            // Use booleanValue for true/false, stringValue for everything else
            Map<String, Object> filterValue;
            String lv = triggerValue.toLowerCase();
            if (lv == 'true' || lv == 'false') {
                filterValue = new Map<String, Object>{ 'booleanValue' => (lv == 'true') };
            } else {
                filterValue = new Map<String, Object>{ 'stringValue' => triggerValue };
            }
            startNode.put('filterLogic', 'and');
            startNode.put('filters', new List<Object>{
                new Map<String, Object>{
                    'field'    => triggerField,
                    'operator' => 'EqualTo',
                    'value'    => filterValue
                }
            });
            // Only fire when the record transitions INTO meeting the condition,
            // not on every update where the field already equals the value.
            startNode.put('doesRequireRecordChangedToMeetCriteria', true);
        } else if (triggerType == 'FIELD_CHANGES' && !String.isBlank(triggerField)) {
            // Fire only when the specified field's value actually changes.
            // IsChanged and doesRequireRecordChangedToMeetCriteria are mutually exclusive —
            // IsChanged is used standalone here without the doesRequire flag.
            startNode.put('filterLogic', 'and');
            startNode.put('filters', new List<Object>{
                new Map<String, Object>{
                    'field'    => triggerField,
                    'operator' => 'IsChanged',
                    'value'    => new Map<String, Object>{ 'booleanValue' => true }
                }
            });
        }

        // Input parameters passed to ExtoleUniversalHandler.invoke():
        //   configKey — static string baked into the flow at deploy time
        //   recordId  — dynamic: the triggering record's Id at runtime
        List<Object> inputParams = new List<Object>{
            new Map<String, Object>{
                'name'  => 'configKey',
                'value' => new Map<String, Object>{ 'stringValue' => configKey }
            },
            new Map<String, Object>{
                'name'  => 'recordId',
                'value' => new Map<String, Object>{ 'elementReference' => '$Record.Id' }
            }
        };

        Map<String, Object> actionCall = new Map<String, Object>{
            'name'            => 'InvokeHandler',
            'label'           => 'Invoke Extole Handler',
            'locationX'       => 50,
            'locationY'       => 200,
            'actionName'      => 'ExtoleUniversalHandler',
            'actionType'      => 'apex',
            'inputParameters' => inputParams
        };

        return new Map<String, Object>{
            'apiVersion'  => Decimal.valueOf(API_VERSION),
            'label'       => flowName,
            'processType' => 'AutoLaunchedFlow',
            'start'       => startNode,
            'status'      => 'Active',
            'actionCalls' => new List<Object>{ actionCall }
        };
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Tooling API lookups
    // ─────────────────────────────────────────────────────────────────────────

    private static String queryFlowDefinitionId(String flowName) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(
                NC_BASE + '/query/?q='
                + EncodingUtil.urlEncode(
                    'SELECT Id FROM FlowDefinition WHERE DeveloperName = \'' + flowName + '\' LIMIT 1',
                    'UTF-8'
                )
            );
            req.setMethod('GET');
            req.setTimeout(30000);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) return null;

            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> records = (List<Object>) result.get('records');
            if (records == null || records.isEmpty()) return null;
            return (String) ((Map<String, Object>) records[0]).get('Id');
        } catch (Exception e) {
            System.debug('ExtoleMetadataService.queryFlowDefinitionId: ' + e.getMessage());
            return null;
        }
    }

    private static List<String> queryFlowVersionIds(String flowName) {
        List<String> ids = new List<String>();
        try {
            // Flow.DeveloperName does not exist in Tooling API — look up via FlowDefinition first
            String defId = queryFlowDefinitionId(flowName);
            if (defId == null) return ids;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(
                NC_BASE + '/query/?q='
                + EncodingUtil.urlEncode(
                    'SELECT Id FROM Flow WHERE DefinitionId = \'' + defId + '\'',
                    'UTF-8'
                )
            );
            req.setMethod('GET');
            req.setTimeout(30000);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) return ids;

            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> records = (List<Object>) result.get('records');
            if (records != null) {
                for (Object r : records) {
                    ids.add((String) ((Map<String, Object>) r).get('Id'));
                }
            }
        } catch (Exception e) {
            System.debug('ExtoleMetadataService.queryFlowVersionIds: ' + e.getMessage());
        }
        return ids;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Error translation
    // ─────────────────────────────────────────────────────────────────────────

    @TestVisible
    static String translateMetadataError(Integer statusCode, String body) {
        if (statusCode == 403) {
            return 'The Named Credential user does not have Customize Application permission. '
                + 'Grant it to the authorized user and retry.';
        }
        if (statusCode == 401) {
            return 'Named Credential authentication failed. Go to Setup → Named Credentials → '
                + 'Extole Tooling and click Authenticate to re-authorize.';
        }
        if (body != null && (body.contains('DUPLICATE_DEVELOPER_NAME') || body.contains('DUPLICATE_VALUE'))) {
            return 'An event config with this name already exists. Delete or deactivate it first.';
        }
        if (body != null && body.contains('INVALID_TYPE')) {
            return 'The trigger object or condition contains an invalid type reference.';
        }
        return 'Metadata API error HTTP ' + statusCode + ': ' + truncate(body, 300);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utility
    // ─────────────────────────────────────────────────────────────────────────

    private static String truncate(String s, Integer maxLen) {
        if (s == null) return '';
        return s.length() > maxLen ? s.substring(0, maxLen) + '…' : s;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Exception type
    // ─────────────────────────────────────────────────────────────────────────

    public class ExtoleMetadataException extends Exception {}
}
