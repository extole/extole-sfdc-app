// Probe: find dashboard runners via v4/v5 report-runners with executor_type filter
// Run with: sf apex run --file scripts/apex/probe_runners_dashboard.apex --target-org extole-sandbox

List<String> endpoints = new List<String>{
    '/v4/report-runners?executor_type=DASHBOARD',
    '/v5/report-runners?executor_type=DASHBOARD',
    '/v4/report-runners?executor_type=DASHBOARD&limit=50',
    '/v4/report-runners'
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
        System.debug('Body (first 1000): ' + body.left(1000));
    }
}
