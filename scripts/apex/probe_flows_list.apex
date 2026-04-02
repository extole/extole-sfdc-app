// Probe: list available flows to understand program flow structure
// Run with: sf apex run --file scripts/apex/probe_flows_list.apex --target-org extole-sandbox

Http http = new Http();

List<String> paths = new List<String>{
    '/v4/flows',
    '/v6/flows',
    '/v4/flow-programs',
    '/v4/zones',
    '/v4/flow-paths',
    '/v4/report-types/summary/parameters'
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
    }
}
