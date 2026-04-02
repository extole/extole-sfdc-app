// Probe: get details of existing summary report to see time_range format
// Run with: sf apex run --file scripts/apex/probe_existing_report_params.apex --target-org extole-sandbox

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v4/reports/tcvkxq33nhd2vgfr4sqa');
req.setMethod('GET');
req.setHeader('Accept', 'application/json');

Http http = new Http();
HttpResponse res = http.send(req);

System.debug('Status: ' + res.getStatusCode());
// Show full params section
String body = res.getBody();
System.debug('Full body (first 2000): ' + body.left(2000));
