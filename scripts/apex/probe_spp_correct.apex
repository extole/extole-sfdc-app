// Probe: summary_per_program with correct ISO date format
// Run with: sf apex run --file scripts/apex/probe_spp_correct.apex --target-org extole-sandbox

String timeRange = '2025-04-02T00:00:00.000-07:00[America/Los_Angeles]/2026-04-02T23:59:59.999-07:00[America/Los_Angeles]';
Http http = new Http();

Map<String, Object> body = new Map<String, Object>{
    'report_type' => 'summary_per_program',
    'parameters' => new Map<String, Object>{
        'time_range' => timeRange,
        'period' => 'MONTH',
        'dimensions' => 'PROGRAM'
    }
};

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v4/reports');
req.setMethod('POST');
req.setHeader('Content-Type', 'application/json');
req.setBody(JSON.serialize(body));
HttpResponse res = http.send(req);
System.debug('Create: ' + res.getStatusCode());

if (res.getStatusCode() == 200) {
    Map<String, Object> r = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    System.debug('ID: ' + r.get('report_id') + ' | Status: ' + r.get('status'));
} else {
    System.debug(res.getBody().left(400));
}
