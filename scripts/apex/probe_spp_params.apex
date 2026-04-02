// Probe: get summary_per_program report type parameters to find valid time_range
// Run with: sf apex run --file scripts/apex/probe_spp_params.apex --target-org extole-sandbox

Http http = new Http();

// Get report type details
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v4/report-types/summary_per_program');
req.setMethod('GET');
req.setHeader('Accept', 'application/json');
HttpResponse res = http.send(req);
System.debug('Type detail status: ' + res.getStatusCode());
System.debug('Body: ' + res.getBody().left(2000));
