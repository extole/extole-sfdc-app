// Probe: look for client config / app endpoints that might list programs
// Run with: sf apex run --file scripts/apex/probe_client_config.apex --target-org extole-sandbox

Http http = new Http();

List<String> paths = new List<String>{
    '/v4/app',
    '/v4/client',
    '/v4/clients/me',
    '/v4/me',
    '/v4/client-config',
    '/v4/program-domains',
    '/v4/campaigns',
    '/v4/experiences',
    '/v2/programs'
};

for (String path : paths) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Extole_API' + path);
    req.setMethod('GET');
    req.setHeader('Accept', 'application/json');
    HttpResponse res = http.send(req);
    System.debug('=== ' + path + ' => ' + res.getStatusCode());
    if (res.getStatusCode() == 200) {
        System.debug(res.getBody().left(300));
    }
}
