// Step 1: create summary report with both flows, get report ID
// Run with: sf apex run --file scripts/apex/probe_create_broad_report.apex --target-org extole-sandbox

String timeRange = '2025-04-02T00:00:00.000-07:00[America/Los_Angeles]/2026-04-02T23:59:59.999-07:00[America/Los_Angeles]';

Map<String, Object> body = new Map<String, Object>{
    'report_type' => 'summary',
    'parameters' => new Map<String, Object>{
        'container' => 'all',
        'flows' => '/business-events,/emails',
        'period' => 'MONTH',
        'time_range' => timeRange,
        'include_totals' => 'false',
        'metric_tags_to_include' => 'dashboard-graph,dashboard-rate',
        'metric_tags_to_exclude' => 'dashboard-exclude'
    }
};

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v4/reports');
req.setMethod('POST');
req.setHeader('Content-Type', 'application/json');
req.setHeader('Accept', 'application/json');
req.setBody(JSON.serialize(body));

Http http = new Http();
HttpResponse res = http.send(req);

System.debug('Status: ' + res.getStatusCode());
System.debug('Body: ' + res.getBody().left(500));
