// PROBE 2b: Log the raw HTTP response from the Tooling API Flow endpoint
// to confirm the exact error before fixing deployViaRestMetadata.

String endpoint = URL.getOrgDomainUrl().toExternalForm()
    + '/services/data/v59.0/tooling/sobjects/Flow/';

// Send a minimal JSON body in the correct Tooling API format to see if JSON works
Map<String, Object> startNode = new Map<String, Object>{
    'locationX'         => 50,
    'locationY'         => 50,
    'connector'         => new Map<String, Object>{ 'targetReference' => 'InvokeHandler' },
    'object'            => 'Lead',
    'recordTriggerType' => 'Create',
    'triggerType'       => 'RecordAfterSave'
};
Map<String, Object> inputParam = new Map<String, Object>{
    'name'  => 'recordIds',
    'value' => new Map<String, Object>{ 'elementReference' => '$Record.Id' }
};
Map<String, Object> actionCall = new Map<String, Object>{
    'name'            => 'InvokeHandler',
    'label'           => 'Invoke Extole Handler',
    'locationX'       => 50,
    'locationY'       => 200,
    'actionName'      => 'Extole_Handler_probe_lead_created',
    'actionType'      => 'apex',
    'inputParameters' => new List<Object>{ inputParam }
};
Map<String, Object> metadata = new Map<String, Object>{
    'apiVersion'    => 59.0,
    'label'         => 'Extole_Flow_probe_lead_created',
    'processType'   => 'AutoLaunchedFlow',
    'start'         => startNode,
    'status'        => 'Active',
    'actionCalls'   => new List<Object>{ actionCall }
};
Map<String, Object> payload = new Map<String, Object>{
    'FullName' => 'Extole_Flow_probe_lead_created',
    'Metadata' => metadata
};

HttpRequest req = new HttpRequest();
req.setEndpoint(endpoint);
req.setMethod('POST');
req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
req.setHeader('Content-Type', 'application/json');
req.setBody(JSON.serialize(payload));
req.setTimeout(60000);

HttpResponse res = new Http().send(req);
System.debug('Probe 2b HTTP status: ' + res.getStatusCode());
System.debug('Probe 2b response body: ' + res.getBody());
