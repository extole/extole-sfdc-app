// Probe: get full runner details including tags for all runners
// Run with: sf apex run --file scripts/apex/probe_runner_tags.apex --target-org extole-sandbox

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v7/report-runners?limit=100');
req.setMethod('GET');
req.setHeader('Accept', 'application/json');

Http http = new Http();
HttpResponse res = http.send(req);

List<Object> runners = (List<Object>) JSON.deserializeUntyped(res.getBody());
System.debug('Total runners: ' + runners.size());

for (Object r : runners) {
    Map<String, Object> runner = (Map<String, Object>) r;
    String name = (String) runner.get('name');
    String id = (String) runner.get('id');
    Object tags = runner.get('tags');
    Object execType = runner.get('executor_type');
    Object reportType = runner.get('report_type');
    System.debug('--- ' + id + ' | ' + name);
    System.debug('    report_type=' + reportType + ' | executor_type=' + execType + ' | tags=' + tags);
}
