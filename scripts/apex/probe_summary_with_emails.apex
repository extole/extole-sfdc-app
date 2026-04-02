// Probe: create summary report with /business-events AND /emails flows
// to see if that surfaces missing programs
// Run with: sf apex run --file scripts/apex/probe_summary_with_emails.apex --target-org extole-sandbox

Http http = new Http();

// Build time range: past year
Datetime now = Datetime.now();
Datetime oneYearAgo = now.addYears(-1);

// Use the same ISO format as the existing report
String tz = 'America/Los_Angeles';
String startStr = oneYearAgo.formatGmt('yyyy-MM-dd') + 'T00:00:00.000-07:00[' + tz + ']';
String endStr = now.formatGmt('yyyy-MM-dd') + 'T23:59:59.999-07:00[' + tz + ']';
String timeRange = startStr + '/' + endStr;

Map<String, Object> body = new Map<String, Object>{
    'report_type' => 'summary',
    'parameters' => new Map<String, Object>{
        'container' => 'all',
        'flows' => '/business-events,/emails',
        'period' => 'MONTH',
        'time_range' => timeRange,
        'include_totals' => 'false',
        'metric_tags_to_include' => 'dashboard-graph,dashboard-rate',
        'metric_tags_to_exclude' => 'dashboard-exclude'
    }
};

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Extole_API/v4/reports');
req.setMethod('POST');
req.setHeader('Content-Type', 'application/json');
req.setHeader('Accept', 'application/json');
req.setBody(JSON.serialize(body));
HttpResponse res = http.send(req);

System.debug('Create status: ' + res.getStatusCode());
System.debug('Body: ' + res.getBody().left(400));

if (res.getStatusCode() != 200) return;

Map<String, Object> report = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
String reportId = (String) report.get('id');
if (String.isBlank(reportId)) reportId = (String) report.get('report_id');
System.debug('Report ID: ' + reportId);

// Poll
Long start = DateTime.now().getTime();
while ((String)report.get('status') != 'DONE' && DateTime.now().getTime() - start < 12000) {
    HttpRequest p = new HttpRequest();
    p.setEndpoint('callout:Extole_API/v4/reports/' + reportId);
    p.setMethod('GET');
    report = (Map<String, Object>) JSON.deserializeUntyped(http.send(p).getBody());
    System.debug('Status: ' + report.get('status'));
}

if ((String)report.get('status') == 'DONE') {
    HttpRequest dl = new HttpRequest();
    dl.setEndpoint('callout:Extole_API/v4/reports/' + reportId + '/download.json');
    dl.setMethod('GET');
    HttpResponse dlRes = http.send(dl);
    if (dlRes.getStatusCode() == 200) {
        List<Object> rows = (List<Object>) JSON.deserializeUntyped(dlRes.getBody());
        Set<String> programs = new Set<String>();
        for (Object row : rows) {
            programs.add((String)((Map<String,Object>)row).get('program'));
        }
        System.debug('Total rows: ' + rows.size() + ' | Programs: ' + programs);
    }
}
