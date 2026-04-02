// Probe: summary report with flow_filter=BEST_FLOW to see if it matches UI program list
// Run with: sf apex run --file scripts/apex/probe_best_flow_report.apex --target-org extole-sandbox

String timeRange = '2025-04-02T00:00:00.000-07:00[America/Los_Angeles]/2026-04-02T23:59:59.999-07:00[America/Los_Angeles]';

Map<String, Object> body = new Map<String, Object>{
    'report_type' => 'summary',
    'parameters' => new Map<String, Object>{
        'container' => 'production',
        'flows' => '/business-events',
        'flow_filter' => 'BEST_FLOW',
        'dimensions' => 'PROGRAM',
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

System.debug('Create status: ' + res.getStatusCode());
Map<String, Object> report = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
String reportId = (String) report.get('report_id');
System.debug('Report ID: ' + reportId + ' | Status: ' + report.get('status'));
