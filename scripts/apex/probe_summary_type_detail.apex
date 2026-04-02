// Probe: get summary report type full detail with parameter options
// Run with: sf apex run --file scripts/apex/probe_summary_type_detail.apex --target-org extole-sandbox

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v4/report-types/summary');
req.setMethod('GET');
req.setHeader('Accept', 'application/json');

Http http = new Http();
HttpResponse res = http.send(req);

System.debug('Status: ' + res.getStatusCode());
System.debug('Full body: ' + res.getBody());
