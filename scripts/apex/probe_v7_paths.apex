// Probe: check v7 paths for programs/flows/report-runners
// Run with: sf apex run --file scripts/apex/probe_v7_paths.apex --target-org extole-sandbox

List<String> endpoints = new List<String>{
    '/v7/report-runners?executor_type=DASHBOARD&limit=50',
    '/v7/report-runners?limit=5',
    '/v5/flows',
    '/v6/flows',
    '/v7/flows',
    '/v6/programs',
    '/v7/programs'
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
        System.debug(res.getBody().left(800));
    } else {
        System.debug(res.getBody().left(200));
    }
}
