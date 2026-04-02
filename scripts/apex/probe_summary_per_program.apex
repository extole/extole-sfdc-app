// Probe: use summary_per_program report type to get all programs
// Run with: sf apex run --file scripts/apex/probe_summary_per_program.apex --target-org extole-sandbox

Http http = new Http();

// Step 1: create the report
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v4/reports');
req.setMethod('POST');
req.setHeader('Content-Type', 'application/json');
req.setHeader('Accept', 'application/json');
req.setBody('{"report_type":"summary_per_program","parameters":{"container":"all","period":"MONTH","time_range":"YEAR"}}');
HttpResponse res = http.send(req);

System.debug('Create status: ' + res.getStatusCode());
System.debug('Create body: ' + res.getBody().left(400));

if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
    return;
}

Map<String, Object> report = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
String reportId = (String) report.get('id');
if (String.isBlank(reportId)) reportId = (String) report.get('report_id');
System.debug('Report ID: ' + reportId);

// Poll for completion
Long startMs = DateTime.now().getTime();
while ((String) report.get('status') != 'DONE' && DateTime.now().getTime() - startMs < 10000) {
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
        System.debug('Total rows: ' + rows.size());
        Set<String> programs = new Set<String>();
        // Look for program field under various key names
        if (!rows.isEmpty()) {
            Map<String, Object> sample = (Map<String, Object>) rows[0];
            System.debug('Sample keys: ' + sample.keySet());
        }
        for (Object row : rows) {
            Map<String, Object> r = (Map<String, Object>) row;
            String prog = (String) r.get('program');
            if (prog == null) prog = (String) r.get('program_label');
            if (prog == null) prog = (String) r.get('campaign');
            programs.add(prog);
        }
        System.debug('Programs found: ' + programs);
    }
}
