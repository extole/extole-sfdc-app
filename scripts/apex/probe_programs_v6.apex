// Probe: try v5/v6 programs endpoints and containers
// Run with: sf apex run --file scripts/apex/probe_programs_v6.apex --target-org extole-sandbox

List<String> endpoints = new List<String>{
    '/v5/programs',
    '/v6/programs',
    '/v4/containers',
    '/v5/containers',
    '/v4/programs?container=all',
    '/v6/report-runners?executor_type=DASHBOARD'
};

Http http = new Http();
for (String path : endpoints) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Extole_API' + path);
    req.setMethod('GET');
    req.setHeader('Accept', 'application/json');
    HttpResponse res = http.send(req);
    System.debug('=== ' + path + ' => ' + res.getStatusCode());
    if (res.getStatusCode() == 200) {
        String body = res.getBody();
        System.debug('Body (first 500): ' + body.left(500));
    }
}
