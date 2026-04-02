// Probe: download existing summary report and list all unique programs
// Run with: sf apex run --file scripts/apex/probe_download_existing_report.apex --target-org extole-sandbox

String reportId = 'tcvkxq33nhd2vgfr4sqa';

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v4/reports/' + reportId + '/download.json');
req.setMethod('GET');
req.setHeader('Accept', 'application/json');
req.setTimeout(30000);

Http http = new Http();
HttpResponse res = http.send(req);

System.debug('Status: ' + res.getStatusCode());

if (res.getStatusCode() == 200) {
    List<Object> rows = (List<Object>) JSON.deserializeUntyped(res.getBody());
    System.debug('Total rows: ' + rows.size());

    Set<String> programs = new Set<String>();
    for (Object row : rows) {
        Map<String, Object> r = (Map<String, Object>) row;
        programs.add((String) r.get('program'));
    }
    System.debug('Unique programs: ' + programs);
} else {
    System.debug('Error: ' + res.getBody().left(300));
}
