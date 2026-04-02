// Step 2: poll and download the broad summary report
// Run with: sf apex run --file scripts/apex/probe_poll_and_download.apex --target-org extole-sandbox

String reportId = 'tcvm0u6n1gsjrnyyl320';
Http http = new Http();

// Check status
HttpRequest statusReq = new HttpRequest();
statusReq.setEndpoint('callout:Extole_API/v4/reports/' + reportId);
statusReq.setMethod('GET');
HttpResponse statusRes = http.send(statusReq);
Map<String, Object> report = (Map<String, Object>) JSON.deserializeUntyped(statusRes.getBody());
String status = (String) report.get('status');
System.debug('Status: ' + status);

if (status == 'DONE') {
    HttpRequest dl = new HttpRequest();
    dl.setEndpoint('callout:Extole_API/v4/reports/' + reportId + '/download.json');
    dl.setMethod('GET');
    HttpResponse dlRes = http.send(dl);
    System.debug('Download HTTP: ' + dlRes.getStatusCode());
    if (dlRes.getStatusCode() == 200) {
        List<Object> rows = (List<Object>) JSON.deserializeUntyped(dlRes.getBody());
        Set<String> programs = new Set<String>();
        for (Object row : rows) {
            programs.add((String)((Map<String,Object>)row).get('program'));
        }
        System.debug('Total rows: ' + rows.size() + ' | Programs: ' + programs);
    }
} else {
    System.debug('Not done yet - run again shortly');
}
