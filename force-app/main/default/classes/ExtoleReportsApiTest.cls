@IsTest
private class ExtoleReportsApiTest {

    private static ExtoleConfig config() {
        return new ExtoleConfig('https://api.extole.io', 'test-token');
    }

    @IsTest
    static void listRunners_returnsRunners() {
        String body = '[{"id":"runner-1","name":"Referral Overview","description":"Weekly"}]';
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, body));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleListReportRunnersRequest().build(config()));
        ExtoleListReportRunnersResponse resp = ExtoleListReportRunnersResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(1, resp.runners.size());
        System.assertEquals('runner-1', resp.runners[0].runnerId);
        System.assertEquals('Referral Overview', resp.runners[0].name);
    }

    @IsTest
    static void listRunners_emptyList_returnsEmpty() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, '[]'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleListReportRunnersRequest().build(config()));
        ExtoleListReportRunnersResponse resp = ExtoleListReportRunnersResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(0, resp.runners.size());
    }

    @IsTest
    static void getLatestReport_statusDone() {
        String body = '[{"report_id":"rpt-1","status":"DONE","created_date":"2026-05-01T00:00:00Z",' +
            '"download_uri":"/v4/reports/rpt-1/download.json"}]';
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, body));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleGetLatestReportRequest('runner-1').build(config()));
        ExtoleGetLatestReportResponse resp = ExtoleGetLatestReportResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals('rpt-1', resp.instance.reportId);
        System.assertEquals('DONE', resp.instance.status);
        System.assertEquals('2026-05-01T00:00:00Z', resp.instance.createdDate);
        System.assert(resp.instance.downloadUri.contains('rpt-1'));
    }

    @IsTest
    static void getLatestReport_statusRunning() {
        String body = '[{"report_id":"rpt-2","status":"RUNNING","created_date":"2026-05-01T00:00:00Z"}]';
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, body));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleGetLatestReportRequest('runner-1').build(config()));
        ExtoleGetLatestReportResponse resp = ExtoleGetLatestReportResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals('RUNNING', resp.instance.status);
    }

    @IsTest
    static void getLatestReport_emptyArray_returnsNullInstance() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, '[]'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleGetLatestReportRequest('runner-1').build(config()));
        ExtoleGetLatestReportResponse resp = ExtoleGetLatestReportResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(null, resp.instance);
    }

    @IsTest
    static void getLatestReport_endpointContainsRunnerIdParam() {
        HttpRequest req = new ExtoleGetLatestReportRequest('runner-1').build(config());
        System.assert(req.getEndpoint().contains('runner_id'));
        System.assert(req.getEndpoint().contains('runner-1'));
    }

    @IsTest
    static void downloadReport_parsesRows() {
        String body = '[{"email":"jane@example.com","reward":"25.00"},{"email":"bob@example.com","reward":"10.00"}]';
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(200, body));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleDownloadReportRequest('rpt-1').build(config()));
        ExtoleDownloadReportResponse resp = ExtoleDownloadReportResponse.fromResponse(raw);
        Test.stopTest();

        System.assertEquals(2, resp.rows.size());
        System.assertEquals('jane@example.com', resp.rows[0].get('email'));
    }

    @IsTest
    static void downloadReport_404_throwsApiException() {
        Test.setMock(HttpCalloutMock.class,
            new ExtoleConfigurableMock().withDefault(404, '{"error":"not_found"}'));

        Test.startTest();
        HttpResponse raw = new ExtoleClient().send(config(),
            new ExtoleDownloadReportRequest('rpt-missing').build(config()));
        Test.stopTest();

        try {
            ExtoleDownloadReportResponse.fromResponse(raw);
            System.assert(false, 'Expected ExtoleApiException');
        } catch (ExtoleApiException e) {
            System.assertEquals(404, e.httpStatus);
        }
    }

    @IsTest
    static void getLatestReport_missingRunnerId_throwsIllegalArgument() {
        try {
            new ExtoleGetLatestReportRequest('').build(config());
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(true);
        }
    }
}
