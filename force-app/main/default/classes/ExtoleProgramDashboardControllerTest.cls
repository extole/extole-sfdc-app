@IsTest
private class ExtoleProgramDashboardControllerTest {
    // ── Programs ─────────────────────────────────────────────────────────────

    @IsTest
    static void testGetProgramsFiltersAndDedupes() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(
                    200,
                    '[' +
                        '{"program_label":"account-openings","state":"LIVE","campaign_type":"MARKETING"},' +
                        '{"program_label":"account-openings","state":"LIVE","campaign_type":"MARKETING"},' + // duplicate
                        '{"program_label":"hubspot-sync","state":"LIVE","campaign_type":"INTEGRATION"},' + // wrong type
                        '{"program_label":"paused-program","state":"PAUSED","campaign_type":"MARKETING"},' + // not LIVE
                        '{"program_label":"","state":"LIVE","campaign_type":"MARKETING"}' + // blank label
                        ']'
                )
        );

        Test.startTest();
        List<Map<String, Object>> programs = ExtoleProgramDashboardController.getPrograms();
        Test.stopTest();

        System.assertEquals(1, programs.size());
        System.assertEquals('account-openings', programs[0].get('label'));
        System.assertEquals('Account Openings', programs[0].get('displayName'));
    }

    // ── Dashboard report lifecycle ───────────────────────────────────────────

    @IsTest
    static void testStartDashboardReportBlankProgramThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            ExtoleProgramDashboardController.startDashboardReport(
                '',
                30,
                'WEEK'
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testStartDashboardReportSuccess() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(200, '{"report_id":"rpt1","status":"PENDING"}')
        );

        Test.startTest();
        Map<String, Object> result = ExtoleProgramDashboardController.startDashboardReport(
            'account-openings',
            30,
            'WEEK'
        );
        Test.stopTest();

        System.assertEquals('rpt1', result.get('reportId'));
        System.assertEquals('PENDING', result.get('status'));
    }

    @IsTest
    static void testPollDashboardReportBlankReportIdThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            ExtoleProgramDashboardController.pollDashboardReport('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testPollDashboardReportStillPending() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(200, '{"report_id":"rpt1","status":"IN_PROGRESS"}')
        );

        Test.startTest();
        Map<String, Object> result = ExtoleProgramDashboardController.pollDashboardReport(
            'rpt1'
        );
        Test.stopTest();

        System.assertEquals('IN_PROGRESS', result.get('status'));
        System.assertEquals(false, result.containsKey('data'));
    }

    @IsTest
    static void testPollDashboardReportDoneParsesFunnel() {
        String downloadJson =
            '[{"period_start":"2026-01-01","period_end":"2026-01-07","time_period":"WEEK","program":"account-openings",' +
            '"steps":[{"step_name":"member_invited","name":"Member Invited","metrics":[' +
            '{"name":"Invites","unit":"#","value":100,"tags":["dashboard-graph"]},' +
            '{"name":"Invite Rate","unit":"%","value":0.5,"tags":["dashboard-rate"]}' +
            ']}]}]';

        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .addPattern('/download.json', 200, downloadJson)
                .withDefault(200, '{"report_id":"rpt1","status":"DONE"}')
        );

        Test.startTest();
        Map<String, Object> result = ExtoleProgramDashboardController.pollDashboardReport(
            'rpt1'
        );
        Test.stopTest();

        System.assertEquals('DONE', result.get('status'));
        Map<String, Object> data = (Map<String, Object>) result.get('data');
        System.assertEquals('account-openings', data.get('program'));

        List<Object> periods = (List<Object>) data.get('periods');
        System.assertEquals(1, periods.size());

        List<Object> steps = (List<Object>) data.get('steps');
        System.assertEquals(1, steps.size());
        Map<String, Object> step = (Map<String, Object>) steps[0];
        System.assertEquals('member_invited', step.get('stepName'));
        Map<String, Object> graphMetric = (Map<String, Object>) step.get(
            'graphMetric'
        );
        System.assertEquals(100, ((List<Object>) graphMetric.get('values'))[0]);
        Map<String, Object> rateMetric = (Map<String, Object>) step.get(
            'rateMetric'
        );
        System.assertEquals(0.5, ((List<Object>) rateMetric.get('values'))[0]);
    }

    @IsTest
    static void testPollDashboardReportDownloadFailureMarksFailed() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .addPattern('/download.json', 500, '{"error":"boom"}')
                .withDefault(200, '{"report_id":"rpt1","status":"DONE"}')
        );

        Test.startTest();
        Map<String, Object> result = ExtoleProgramDashboardController.pollDashboardReport(
            'rpt1'
        );
        Test.stopTest();

        System.assertEquals('FAILED', result.get('status'));
        System.assertNotEquals(null, result.get('error'));
    }

    // ── Promotions lifecycle ─────────────────────────────────────────────────

    @IsTest
    static void testStartPromotionsReportBlankProgramThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            ExtoleProgramDashboardController.startPromotionsReport(
                null,
                30,
                'WEEK'
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testStartPromotionsReportSuccess() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(200, '{"report_id":"rpt2","status":"PENDING"}')
        );

        Test.startTest();
        Map<String, Object> result = ExtoleProgramDashboardController.startPromotionsReport(
            'account-openings',
            30,
            'WEEK'
        );
        Test.stopTest();

        System.assertEquals('rpt2', result.get('reportId'));
    }

    @IsTest
    static void testPollPromotionsReportSortsByTotalDescending() {
        String downloadJson =
            '[' +
            '{"period_start":"2026-01-01","period_end":"2026-01-07","time_period":"WEEK",' +
            '"source_type":"link","source":"global_footer",' +
            '"steps":[{"metrics":[' +
            '{"name":"Shares","value":10,"tags":["promotion-bar:shares"]},' +
            '{"name":"Share Rate","value":0.1,"tags":["promotion:shares"]}' +
            ']}]},' +
            '{"period_start":"2026-01-01","period_end":"2026-01-07","time_period":"WEEK",' +
            '"source_type":"link","source":"header",' +
            '"steps":[{"metrics":[' +
            '{"name":"Shares","value":50,"tags":["promotion-bar:shares"]},' +
            '{"name":"Share Rate","value":0.4,"tags":["promotion:shares"]}' +
            ']}]}' +
            ']';

        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .addPattern('/download.json', 200, downloadJson)
                .withDefault(200, '{"report_id":"rpt2","status":"DONE"}')
        );

        Test.startTest();
        Map<String, Object> result = ExtoleProgramDashboardController.pollPromotionsReport(
            'rpt2'
        );
        Test.stopTest();

        Map<String, Object> data = (Map<String, Object>) result.get('data');
        List<Object> promotions = (List<Object>) data.get('promotions');
        System.assertEquals(2, promotions.size());
        // Highest total ("header", 50) sorts first.
        Map<String, Object> first = (Map<String, Object>) promotions[0];
        System.assertEquals('header', first.get('source'));
        System.assertEquals('Header', first.get('displayName'));
        System.assertEquals(50, first.get('total'));
    }

    // ── Channels lifecycle ───────────────────────────────────────────────────

    @IsTest
    static void testStartChannelsReportBlankProgramThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            ExtoleProgramDashboardController.startChannelsReport('', 30);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testStartChannelsReportSuccess() {
        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .withDefault(200, '{"report_id":"rpt3","status":"PENDING"}')
        );

        Test.startTest();
        Map<String, Object> result = ExtoleProgramDashboardController.startChannelsReport(
            'account-openings',
            30
        );
        Test.stopTest();

        System.assertEquals('rpt3', result.get('reportId'));
    }

    @IsTest
    static void testPollChannelsReportParsesAndSortsBySharesDescending() {
        String downloadJson =
            '[' +
            '{"channel":"EMAIL","steps":[' +
            '{"step_name":"shared","metrics":[{"name":"Shares","value":100,"tags":["channel"]}]},' +
            '{"step_name":"share_click","metrics":[{"name":"Share CTR","value":2.5,"tags":["channel-rate"]}]},' +
            '{"step_name":"account_opened","metrics":[' +
            '{"name":"Opens","value":10,"tags":["channel"]},' +
            '{"name":"Conversion Rate","value":10.0,"tags":["channel-rate"]}' +
            ']}' +
            ']},' +
            '{"channel":"SMS","steps":[' +
            '{"step_name":"shared","metrics":[{"name":"Shares","value":500,"tags":["channel"]}]},' +
            '{"step_name":"share_click","metrics":[{"name":"Share CTR","value":1.5,"tags":["channel-rate"]}]},' +
            '{"step_name":"account_opened","metrics":[' +
            '{"name":"Opens","value":20,"tags":["channel"]},' +
            '{"name":"Conversion Rate","value":4.0,"tags":["channel-rate"]}' +
            ']}' +
            ']}' +
            ']';

        Test.setMock(
            HttpCalloutMock.class,
            new ExtoleConfigurableMock()
                .addPattern('/download.json', 200, downloadJson)
                .withDefault(200, '{"report_id":"rpt3","status":"DONE"}')
        );

        Test.startTest();
        Map<String, Object> result = ExtoleProgramDashboardController.pollChannelsReport(
            'rpt3'
        );
        Test.stopTest();

        Map<String, Object> data = (Map<String, Object>) result.get('data');
        List<Object> channels = (List<Object>) data.get('channels');
        System.assertEquals(2, channels.size());
        // SMS has more shares (500 > 100), so it sorts first.
        Map<String, Object> first = (Map<String, Object>) channels[0];
        System.assertEquals('SMS', first.get('channel'));
        System.assertEquals('Sms', first.get('displayName'));
        System.assertEquals(500, first.get('shares'));
        System.assertEquals(20, first.get('accountOpenings'));
        System.assertEquals(4.0, first.get('conversionRate'));
    }
}
