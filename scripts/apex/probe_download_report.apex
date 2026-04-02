// Generic: poll and download a report by ID, list unique programs
// Run with: sf apex run --file scripts/apex/probe_download_report.apex --target-org extole-sandbox

String reportId = 'tcvmdb1nrg6la54hh2uj';  // CHANGE THIS
Http http = new Http();

HttpRequest statusReq = new HttpRequest();
statusReq.setEndpoint('callout:Extole_API/v4/reports/' + reportId);
statusReq.setMethod('GET');
Map<String, Object> report = (Map<String, Object>) JSON.deserializeUntyped(http.send(statusReq).getBody());
String status = (String) report.get('status');
System.debug('Status: ' + status);

if (status != 'DONE') {
    System.debug('Not done yet');
    return;
}

HttpRequest dl = new HttpRequest();
dl.setEndpoint('callout:Extole_API/v4/reports/' + reportId + '/download.json');
dl.setMethod('GET');
HttpResponse dlRes = http.send(dl);
System.debug('Download HTTP: ' + dlRes.getStatusCode());

List<Object> rows = (List<Object>) JSON.deserializeUntyped(dlRes.getBody());
Set<String> programs = new Set<String>();
for (Object row : rows) {
    programs.add((String)((Map<String,Object>)row).get('program'));
}
System.debug('Total rows: ' + rows.size() + ' | Programs: ' + programs);
