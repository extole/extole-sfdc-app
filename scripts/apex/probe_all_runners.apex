// Probe: get all report runners, look for DASHBOARD executor_type
// Run with: sf apex run --file scripts/apex/probe_all_runners.apex --target-org extole-sandbox

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v7/report-runners?limit=100');
req.setMethod('GET');
req.setHeader('Accept', 'application/json');

Http http = new Http();
HttpResponse res = http.send(req);

System.debug('Status: ' + res.getStatusCode());

// Parse and find DASHBOARD executor_type runners
String body = res.getBody();
// Just log unique combinations of id, name, executor_type
List<Object> runners = (List<Object>) JSON.deserializeUntyped(body);
System.debug('Total runners: ' + runners.size());

for (Object r : runners) {
    Map<String, Object> runner = (Map<String, Object>) r;
    String execType = (String) runner.get('executor_type');
    String name = (String) runner.get('name');
    String id = (String) runner.get('id');
    System.debug('Runner: ' + id + ' | ' + name + ' | executor_type=' + execType);
}
