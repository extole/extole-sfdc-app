// Probe: dashboard report - check error and try different params
// Run with: sf apex run --file scripts/apex/probe_dashboard_report_wide2.apex --target-org extole-sandbox

Http http = new Http();

// Try 1: minimal params matching what worked before
HttpRequest req1 = new HttpRequest();
req1.setEndpoint('callout:Extole_API/v4/reports');
req1.setMethod('POST');
req1.setHeader('Content-Type', 'application/json');
req1.setHeader('Accept', 'application/json');
req1.setBody('{"report_type":"PROGRAM_DASHBOARD","parameters":{"container":"all","dimensions":"PROGRAM","time_range":"YEAR","period":"MONTH"}}');
HttpResponse res1 = http.send(req1);
System.debug('Try1 Status: ' + res1.getStatusCode());
System.debug('Try1 Body: ' + res1.getBody().left(300));

// Try 2: TRAILING_YEAR
HttpRequest req2 = new HttpRequest();
req2.setEndpoint('callout:Extole_API/v4/reports');
req2.setMethod('POST');
req2.setHeader('Content-Type', 'application/json');
req2.setHeader('Accept', 'application/json');
req2.setBody('{"report_type":"PROGRAM_DASHBOARD","parameters":{"container":"all","dimensions":"PROGRAM","time_range":"TRAILING_MONTH","period":"DAY"}}');
HttpResponse res2 = http.send(req2);
System.debug('Try2 Status: ' + res2.getStatusCode());
System.debug('Try2 Body: ' + res2.getBody().left(300));
