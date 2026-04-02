// Probe: try to enumerate valid program labels from API
// Run with: sf apex run --file scripts/apex/probe_program_labels.apex --target-org extole-sandbox

Http http = new Http();

List<String> paths = new List<String>{
    '/v4/program-labels',
    '/v4/report-types/summary/values/program',
    '/v4/report-types/summary/parameters/program',
    '/v4/client-program-labels',
    '/v4/client/program-labels'
};

for (String path : paths) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Extole_API' + path);
    req.setMethod('GET');
    req.setHeader('Accept', 'application/json');
    HttpResponse res = http.send(req);
    System.debug('=== ' + path + ' => ' + res.getStatusCode());
    if (res.getStatusCode() == 200) {
        System.debug(res.getBody().left(500));
    }
}
