// Probe: inspect the structure of rows in the broad report
// Run with: sf apex run --file scripts/apex/probe_inspect_rows.apex --target-org extole-sandbox

String reportId = 'tcvm0u6n1gsjrnyyl320';
Http http = new Http();

HttpRequest dl = new HttpRequest();
dl.setEndpoint('callout:Extole_API/v4/reports/' + reportId + '/download.json');
dl.setMethod('GET');
HttpResponse dlRes = http.send(dl);

List<Object> rows = (List<Object>) JSON.deserializeUntyped(dlRes.getBody());
System.debug('Total rows: ' + rows.size());

// Show first 3 rows' keys and program/time_period values
for (Integer i = 0; i < Math.min(3, rows.size()); i++) {
    Map<String, Object> row = (Map<String, Object>) rows[i];
    System.debug('Row ' + i + ' keys: ' + row.keySet());
    System.debug('Row ' + i + ' period_start: ' + row.get('period_start') + ' program: ' + row.get('program') + ' time_period: ' + row.get('time_period'));
}
