// Probe: find valid report types via API
// Run with: sf apex run --file scripts/apex/probe_report_types.apex --target-org extole-sandbox

Http http = new Http();

List<String> paths = new List<String>{
    '/v4/report-types',
    '/v5/report-types',
    '/v6/report-types',
    '/v4/reports?limit=5',
    '/v4/reports?tag=internal%3Adashboard&limit=10'
};

for (String path : paths) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Extole_API' + path);
    req.setMethod('GET');
    req.setHeader('Accept', 'application/json');
    HttpResponse res = http.send(req);
    System.debug('=== ' + path + ' => ' + res.getStatusCode());
    if (res.getStatusCode() == 200) {
        System.debug(res.getBody().left(600));
    } else {
        System.debug(res.getBody().left(200));
    }
}
