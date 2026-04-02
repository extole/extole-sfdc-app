// Probe: get all programs from /v2/programs
// Run with: sf apex run --file scripts/apex/probe_v2_programs.apex --target-org extole-sandbox

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v2/programs');
req.setMethod('GET');
req.setHeader('Accept', 'application/json');

Http http = new Http();
HttpResponse res = http.send(req);

System.debug('Status: ' + res.getStatusCode());

List<Object> programs = (List<Object>) JSON.deserializeUntyped(res.getBody());
System.debug('Total programs: ' + programs.size());

for (Object p : programs) {
    Map<String, Object> prog = (Map<String, Object>) p;
    System.debug('id=' + prog.get('id') + ' name=' + prog.get('name') + ' domain=' + prog.get('domain'));
}
