// Probe: try various report body formats to match the Extole UI dashboard report
// Run with: sf apex run --file scripts/apex/probe_dashboard_exact_params.apex --target-org extole-sandbox

Http http = new Http();

// Try 1: executor_type at top level (not inside parameters)
String body1 = JSON.serialize(new Map<String, Object>{
    'executor_type' => 'DASHBOARD',
    'parameters' => new Map<String, Object>{
        'container' => 'production',
        'dimensions' => 'PROGRAM',
        'period' => 'MONTH',
        'time_range' => 'YEAR',
        'include_totals' => true
    }
});

HttpRequest req1 = new HttpRequest();
req1.setEndpoint('callout:Extole_API/v4/reports');
req1.setMethod('POST');
req1.setHeader('Content-Type', 'application/json');
req1.setHeader('Accept', 'application/json');
req1.setBody(body1);
HttpResponse res1 = http.send(req1);
System.debug('Try1 (executor_type top-level): ' + res1.getStatusCode());
System.debug(res1.getBody().left(300));

// Try 2: STEP_CONVERSION report_type (common for funnel/program reports)
String body2 = JSON.serialize(new Map<String, Object>{
    'report_type' => 'STEP_CONVERSION',
    'parameters' => new Map<String, Object>{
        'container' => 'production',
        'dimensions' => 'PROGRAM',
        'period' => 'MONTH',
        'time_range' => 'YEAR'
    }
});
HttpRequest req2 = new HttpRequest();
req2.setEndpoint('callout:Extole_API/v4/reports');
req2.setMethod('POST');
req2.setHeader('Content-Type', 'application/json');
req2.setHeader('Accept', 'application/json');
req2.setBody(body2);
HttpResponse res2 = http.send(req2);
System.debug('Try2 (STEP_CONVERSION): ' + res2.getStatusCode());
System.debug(res2.getBody().left(300));
