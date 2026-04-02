// Probe: list programs via Extole programs API
// Run with: sf apex run --file scripts/apex/probe_programs_list.apex --target-org extole-sandbox

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v4/programs');
req.setMethod('GET');
req.setHeader('Accept', 'application/json');

Http http = new Http();
HttpResponse res = http.send(req);

System.debug('Status: ' + res.getStatusCode());
System.debug('Body: ' + res.getBody());
