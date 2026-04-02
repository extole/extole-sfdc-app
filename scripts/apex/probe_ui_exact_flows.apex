// Probe: use exact flow paths shown in Extole UI dashboard report
// Run with: sf apex run --file scripts/apex/probe_ui_exact_flows.apex --target-org extole-sandbox

String timeRange = '2025-04-02T00:00:00.000-07:00[America/Los_Angeles]/2026-04-02T23:59:59.999-07:00[America/Los_Angeles]';
Http http = new Http();

// Try 1: exact UI flows with spaces
Map<String, Object> body1 = new Map<String, Object>{
    'report_type' => 'summary',
    'parameters' => new Map<String, Object>{
        'container' => 'production',
        'flows' => '/Business Events/,/Emails/*',
        'flow_filter' => 'BEST_FLOW',
        'dimensions' => 'PROGRAM',
        'period' => 'MONTH',
        'time_range' => timeRange,
        'include_totals' => 'false'
    }
};

HttpRequest req1 = new HttpRequest();
req1.setEndpoint('callout:Extole_API/v4/reports');
req1.setMethod('POST');
req1.setHeader('Content-Type', 'application/json');
req1.setBody(JSON.serialize(body1));
HttpResponse res1 = http.send(req1);
System.debug('Try1 (UI exact flows): ' + res1.getStatusCode());
System.debug(res1.getBody().left(300));

// Try 2: container=all with UI flows
Map<String, Object> body2 = new Map<String, Object>{
    'report_type' => 'summary',
    'parameters' => new Map<String, Object>{
        'container' => 'all',
        'flows' => '/Business Events/,/Emails/*',
        'flow_filter' => 'BEST_FLOW',
        'dimensions' => 'PROGRAM',
        'period' => 'MONTH',
        'time_range' => timeRange,
        'include_totals' => 'false'
    }
};

HttpRequest req2 = new HttpRequest();
req2.setEndpoint('callout:Extole_API/v4/reports');
req2.setMethod('POST');
req2.setHeader('Content-Type', 'application/json');
req2.setBody(JSON.serialize(body2));
HttpResponse res2 = http.send(req2);
System.debug('Try2 (all + UI flows): ' + res2.getStatusCode());
Map<String, Object> r2 = (Map<String, Object>) JSON.deserializeUntyped(res2.getBody());
System.debug('Report ID: ' + r2.get('report_id') + ' Status: ' + r2.get('status'));
