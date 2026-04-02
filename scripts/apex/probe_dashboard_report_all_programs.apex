// Probe: create dashboard report with PROGRAM dimension to discover all programs
// Run with: sf apex run --file scripts/apex/probe_dashboard_report_all_programs.apex --target-org extole-sandbox

Http http = new Http();

// Try report_type=DASHBOARD with PROGRAM dimension and all containers
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v4/reports');
req.setMethod('POST');
req.setHeader('Content-Type', 'application/json');
req.setHeader('Accept', 'application/json');
req.setBody('{"report_type":"DASHBOARD","parameters":{"container":"all","dimensions":"PROGRAM","time_range":"TRAILING_MONTH","period":"MONTH"}}');
HttpResponse res = http.send(req);

System.debug('Status: ' + res.getStatusCode());
System.debug('Body: ' + res.getBody().left(500));

if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
    Map<String, Object> report = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    String reportId = (String) report.get('id');
    String status = (String) report.get('status');
    System.debug('Report ID: ' + reportId + ' Status: ' + status);

    // Wait a moment then check status
    Long startMs = DateTime.now().getTime();
    while ((String) report.get('status') != 'DONE' && DateTime.now().getTime() - startMs < 8000) {
        HttpRequest pollReq = new HttpRequest();
        pollReq.setEndpoint('callout:Extole_API/v4/reports/' + reportId);
        pollReq.setMethod('GET');
        HttpResponse pollRes = http.send(pollReq);
        report = (Map<String, Object>) JSON.deserializeUntyped(pollRes.getBody());
        System.debug('Poll status: ' + report.get('status'));
    }

    if ((String) report.get('status') == 'DONE') {
        HttpRequest dlReq = new HttpRequest();
        dlReq.setEndpoint('callout:Extole_API/v4/reports/' + reportId + '/download.json');
        dlReq.setMethod('GET');
        HttpResponse dlRes = http.send(dlReq);
        System.debug('Download status: ' + dlRes.getStatusCode());

        if (dlRes.getStatusCode() == 200) {
            List<Object> rows = (List<Object>) JSON.deserializeUntyped(dlRes.getBody());
            Set<String> programs = new Set<String>();
            for (Object row : rows) {
                Map<String, Object> r = (Map<String, Object>) row;
                programs.add((String) r.get('program'));
            }
            System.debug('Programs found: ' + programs);
        }
    }
}
