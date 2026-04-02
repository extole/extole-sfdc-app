// Probe: get all report types and look for program/dashboard related ones
// Run with: sf apex run --file scripts/apex/probe_report_types_full.apex --target-org extole-sandbox

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v4/report-types?limit=100');
req.setMethod('GET');
req.setHeader('Accept', 'application/json');

Http http = new Http();
HttpResponse res = http.send(req);

System.debug('Status: ' + res.getStatusCode());

List<Object> types = (List<Object>) JSON.deserializeUntyped(res.getBody());
System.debug('Total report types: ' + types.size());

for (Object t : types) {
    Map<String, Object> rt = (Map<String, Object>) t;
    String name = (String) rt.get('name');
    String displayName = (String) rt.get('display_name');
    String execType = (String) rt.get('executor_type');
    System.debug(name + ' | ' + displayName + ' | executor_type=' + execType);
}
