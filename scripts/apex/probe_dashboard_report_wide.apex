// Probe: dashboard report with wider time range to find all programs
// Run with: sf apex run --file scripts/apex/probe_dashboard_report_wide.apex --target-org extole-sandbox

// Step 1: Create report with YEAR time_range to catch newer/older programs
HttpRequest createReq = new HttpRequest();
createReq.setEndpoint('callout:Extole_API/v4/reports');
createReq.setMethod('POST');
createReq.setHeader('Content-Type', 'application/json');
createReq.setHeader('Accept', 'application/json');

String body = '{"report_type":"PROGRAM_DASHBOARD","parameters":{"container":"all","dimensions":"PROGRAM","time_range":"TRAILING_MONTH","period":"MONTH"}}';
createReq.setBody(body);

Http http = new Http();
HttpResponse createRes = http.send(createReq);

System.debug('Create Status: ' + createRes.getStatusCode());
Map<String, Object> report = (Map<String, Object>) JSON.deserializeUntyped(createRes.getBody());
String reportId = (String) report.get('id');
System.debug('Report ID: ' + reportId);
System.debug('Status: ' + report.get('status'));
