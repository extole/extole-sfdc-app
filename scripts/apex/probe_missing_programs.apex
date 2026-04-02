// Probe: check if missing programs exist as valid program labels
// Run with: sf apex run --file scripts/apex/probe_missing_programs.apex --target-org extole-sandbox

String timeRange = '2025-04-02T00:00:00.000-07:00[America/Los_Angeles]/2026-04-02T23:59:59.999-07:00[America/Los_Angeles]';
Http http = new Http();

List<String> testPrograms = new List<String>{
    'refer-a-member-with-in-branch',
    'refer_a_member_with_in_branch',
    'small-business-deposits',
    'small_business_deposits',
    'reward-bank'
};

for (String prog : testPrograms) {
    Map<String, Object> body = new Map<String, Object>{
        'report_type' => 'summary',
        'parameters' => new Map<String, Object>{
            'container' => 'all',
            'flows' => '/business-events',
            'dimensions' => 'PROGRAM',
            'period' => 'MONTH',
            'time_range' => timeRange,
            'include_totals' => 'false',
            'program' => prog
        }
    };

    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Extole_API/v4/reports');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setHeader('Accept', 'application/json');
    req.setBody(JSON.serialize(body));
    HttpResponse res = http.send(req);
    System.debug('program=' + prog + ' => ' + res.getStatusCode() + ' | ' + res.getBody().left(150));
}
