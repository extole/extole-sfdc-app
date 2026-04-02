// PROBE 4: Fire a direct callout to Extole and log the HTTP response
// Confirms the Named Credential + endpoint are working correctly.
// Run with: sf apex run --file scripts/apex/probe_4_verify_callout.apex -o extole-sandbox

Map<String, Object> dataMap = new Map<String, Object>{
    'email'      => 'probe-verify-' + DateTime.now().getTime() + '@extole-test.com',
    'first_name' => 'ProbeTest',
    'last_name'  => 'Verify',
    'app_type'   => 'salesforce_crm'
};

Map<String, Object> payload = new Map<String, Object>{
    'event_name' => 'sfdc_lead_created',
    'data'       => dataMap
};

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v5/events');
req.setMethod('POST');
req.setHeader('Content-Type', 'application/json');
req.setBody(JSON.serialize(payload));
req.setTimeout(30000);

HttpResponse res = new Http().send(req);
System.debug('Probe 4 HTTP status: ' + res.getStatusCode());
System.debug('Probe 4 response body: ' + res.getBody());
