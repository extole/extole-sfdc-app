// Probe: get all reports tagged internal:dashboard to see which programs have dashboards
// Run with: sf apex run --file scripts/apex/probe_dashboard_tagged_reports.apex --target-org extole-sandbox

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v4/reports?tag=internal%3Adashboard&limit=50');
req.setMethod('GET');
req.setHeader('Accept', 'application/json');

Http http = new Http();
HttpResponse res = http.send(req);
System.debug('Status: ' + res.getStatusCode());

List<Object> reports = (List<Object>) JSON.deserializeUntyped(res.getBody());
System.debug('Total reports: ' + reports.size());

for (Object r : reports) {
    Map<String, Object> report = (Map<String, Object>) r;
    Map<String, Object> params = (Map<String, Object>) report.get('parameters');
    String program = null;
    if (params != null) {
        Map<String, Object> programParam = (Map<String, Object>) params.get('program');
        if (programParam != null) program = (String) programParam.get('value');
    }
    System.debug('id=' + report.get('report_id') + ' name=' + report.get('name') + ' program=' + program + ' status=' + report.get('status'));
}
