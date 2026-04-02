// Probe: list DASHBOARD type report runners
// Run with: sf apex run --file scripts/apex/probe_dashboard_runners.apex --target-org extole-sandbox

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v7/report-runners?type=DASHBOARD');
req.setMethod('GET');
req.setHeader('Accept', 'application/json');

Http http = new Http();
HttpResponse res = http.send(req);

System.debug('Status: ' + res.getStatusCode());
System.debug('Body: ' + res.getBody());
