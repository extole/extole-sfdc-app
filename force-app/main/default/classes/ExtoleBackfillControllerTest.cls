@IsTest
private class ExtoleBackfillControllerTest {
    private class CampaignsMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '[{"program_label":"referral-program","name":"Referral Program"},' +
                '{"program_label":"test-program","name":"Test Program"}]'
            );
            return res;
        }
    }

    private class FailingMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }

    // ─── getShareLinkFieldSetting ────────────────────────────────────────────

    @IsTest
    static void testGetShareLinkFieldSetting_defaultsToStandardFieldWhenUnset() {
        String field = ExtoleBackfillController.getShareLinkFieldSetting(
            'Contact'
        );
        System.assertEquals('Extole_Share_Link__c', field);
    }

    @IsTest
    static void testGetShareLinkFieldSetting_leadUsesLeadSetting() {
        upsert new Extole_App_Settings__c(
            Lead_Share_Link_Field__c = 'Extole_Share_Link__c'
        );
        String field = ExtoleBackfillController.getShareLinkFieldSetting(
            'Lead'
        );
        System.assertEquals('Extole_Share_Link__c', field);
    }

    @IsTest
    static void testGetShareLinkFieldSetting_nonExistentFieldReturnsNull() {
        upsert new Extole_App_Settings__c(
            Contact_Share_Link_Field__c = 'Not_A_Real_Field__x'
        );
        String field = ExtoleBackfillController.getShareLinkFieldSetting(
            'Contact'
        );
        System.assertEquals(null, field);
    }

    // ─── getWritebackFields ───────────────────────────────────────────────────

    @IsTest
    static void testGetWritebackFieldsContactNotNull() {
        List<Map<String, String>> fields = ExtoleBackfillController.getWritebackFields(
            'Contact'
        );
        System.assertNotEquals(
            null,
            fields,
            'Should return non-null list for Contact'
        );
    }

    @IsTest
    static void testGetWritebackFieldsContactHasShareLinkField() {
        List<Map<String, String>> fields = ExtoleBackfillController.getWritebackFields(
            'Contact'
        );
        Boolean found = false;
        for (Map<String, String> f : fields) {
            if (f.get('value') == 'Extole_Share_Link__c') {
                found = true;
                break;
            }
        }
        System.assert(
            found,
            'Contact should have Extole_Share_Link__c in writable fields'
        );
    }

    @IsTest
    static void testGetWritebackFieldsLeadHasShareLinkField() {
        List<Map<String, String>> fields = ExtoleBackfillController.getWritebackFields(
            'Lead'
        );
        Boolean found = false;
        for (Map<String, String> f : fields) {
            if (f.get('value') == 'Extole_Share_Link__c') {
                found = true;
                break;
            }
        }
        System.assert(
            found,
            'Lead should have Extole_Share_Link__c in writable fields'
        );
    }

    @IsTest
    static void testGetWritebackFieldsInvalidObjectReturnsEmpty() {
        List<Map<String, String>> fields = ExtoleBackfillController.getWritebackFields(
            'NoSuchObject__x'
        );
        System.assertEquals(
            0,
            fields.size(),
            'Should return empty list for unknown object'
        );
    }

    @IsTest
    static void testGetWritebackFieldsHasLabelAndValue() {
        List<Map<String, String>> fields = ExtoleBackfillController.getWritebackFields(
            'Contact'
        );
        for (Map<String, String> f : fields) {
            System.assertNotEquals(
                null,
                f.get('label'),
                'Each field entry should have a label key'
            );
            System.assertNotEquals(
                null,
                f.get('value'),
                'Each field entry should have a value key'
            );
        }
    }

    // ─── getExtoleCampaigns ───────────────────────────────────────────────────

    @IsTest
    static void testGetExtoleCampaignsReturnsSortedOptions() {
        Test.setMock(HttpCalloutMock.class, new CampaignsMock());
        Test.startTest();
        List<Map<String, String>> options = ExtoleBackfillController.getExtoleCampaigns();
        Test.stopTest();

        System.assertEquals(
            2,
            options.size(),
            'Should return 2 mock campaigns'
        );
        System.assertEquals(
            'referral-program',
            options[0].get('value'),
            'First option should be referral-program (alpha)'
        );
        System.assertEquals(
            'test-program',
            options[1].get('value'),
            'Second option should be test-program'
        );
    }

    @IsTest
    static void testGetExtoleCampaignsApiFailureReturnsEmpty() {
        Test.setMock(HttpCalloutMock.class, new FailingMock());
        Test.startTest();
        List<Map<String, String>> options = ExtoleBackfillController.getExtoleCampaigns();
        Test.stopTest();

        System.assertNotEquals(
            null,
            options,
            'Should return non-null on API failure'
        );
        System.assertEquals(
            0,
            options.size(),
            'Should return empty list on API failure'
        );
    }

    private class MalformedJsonMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('not valid json{{{');
            return res;
        }
    }

    @IsTest
    static void testGetExtoleCampaigns_malformedResponseReturnsEmpty() {
        Test.setMock(HttpCalloutMock.class, new MalformedJsonMock());
        Test.startTest();
        List<Map<String, String>> options = ExtoleBackfillController.getExtoleCampaigns();
        Test.stopTest();
        System.assertEquals(0, options.size());
    }

    // ─── getReports ──────────────────────────────────────────────────────────

    @IsTest
    static void testGetReportsNotNull() {
        List<Map<String, String>> reports = ExtoleBackfillController.getReports(
            ''
        );
        System.assertNotEquals(null, reports, 'Should return non-null list');
    }

    @IsTest(SeeAllData=true)
    static void testGetReportsWithSearchTermFilters() {
        List<Map<String, String>> reports = ExtoleBackfillController.getReports(
            'Audience Sync Test Leads'
        );
        Boolean found = false;
        for (Map<String, String> r : reports) {
            if (r.get('label') == 'Audience Sync Test Leads')
                found = true;
        }
        System.assertEquals(true, found);
    }

    // ─── previewCount ─────────────────────────────────────────────────────────

    @IsTest
    static void testPreviewCountDateFilterContactMatchesToday() {
        insert new Contact(
            FirstName = 'Count',
            LastName = 'Test',
            Email = 'counttest@extole-test.com'
        );
        String yesterday = String.valueOf(Date.today().addDays(-1));
        Integer count = ExtoleBackfillController.previewCount(
            'Contact',
            'date',
            yesterday,
            null
        );
        System.assert(
            count >= 1,
            'Should count contacts created on or after yesterday'
        );
    }

    @IsTest
    static void testPreviewCountDateFilterFutureDateReturnsZero() {
        String tomorrow = String.valueOf(Date.today().addDays(1));
        Integer count = ExtoleBackfillController.previewCount(
            'Contact',
            'date',
            tomorrow,
            null
        );
        System.assertEquals(0, count, 'Future date should return 0');
    }

    @IsTest
    static void testPreviewCountDefaultLeadCountsUnconverted() {
        insert new Lead(
            FirstName = 'Count',
            LastName = 'Lead',
            Email = 'countlead@extole-test.com',
            Company = 'Test'
        );
        Integer count = ExtoleBackfillController.previewCount(
            'Lead',
            'default',
            null,
            null
        );
        System.assert(
            count >= 1,
            'Should count at least the unconverted lead with email'
        );
    }

    @IsTest
    static void testPreviewCountDefaultContactRequiresClosedWonOpp() {
        insert new Contact(
            FirstName = 'No',
            LastName = 'Opp',
            Email = 'noopp@extole-test.com'
        );
        Integer count = ExtoleBackfillController.previewCount(
            'Contact',
            'default',
            null,
            null
        );
        System.assertEquals(
            0,
            count,
            'Contact without Closed Won opp should not count in default filter'
        );
    }

    @IsTest
    static void testPreviewCountDateFilterLead() {
        insert new Lead(
            FirstName = 'Count',
            LastName = 'DateLead',
            Email = 'countdatelead@extole-test.com',
            Company = 'Test'
        );
        String yesterday = String.valueOf(Date.today().addDays(-1));
        Integer count = ExtoleBackfillController.previewCount(
            'Lead',
            'date',
            yesterday,
            null
        );
        System.assert(
            count >= 1,
            'Should count unconverted leads with email created on or after yesterday'
        );
    }

    @IsTest(SeeAllData=true)
    static void testPreviewCountReportAudience() {
        Id reportId = [
            SELECT Id
            FROM Report
            WHERE DeveloperName = 'Audience_Sync_Test_Leads'
            LIMIT 1
        ]
        .Id;
        Integer count = ExtoleBackfillController.previewCount(
            'Lead',
            'report',
            null,
            reportId
        );
        System.assert(count >= 0);
    }

    // ─── startBackfill ────────────────────────────────────────────────────────

    @IsTest
    static void testStartBackfillCreatesLogInProgress() {
        // Don't use startTest/stopTest here — we want to verify the log state BEFORE
        // the queueable runs, and stopTest() flushes the queue synchronously.
        Id logId = ExtoleBackfillController.startBackfill(
            'Contact',
            'default',
            null,
            null,
            'Extole_Share_Link__c',
            '',
            ''
        );

        System.assertNotEquals(null, logId, 'Should return a log ID');
        Extole_Backfill_Log__c log = [
            SELECT Status__c, Object_Type__c, Audience_Type__c, Target_Field__c
            FROM Extole_Backfill_Log__c
            WHERE Id = :logId
        ];
        System.assertEquals(
            'IN_PROGRESS',
            log.Status__c,
            'Initial status should be IN_PROGRESS'
        );
        System.assertEquals(
            'Contact',
            log.Object_Type__c,
            'Object type should be Contact'
        );
        System.assertEquals(
            'Default Filter',
            log.Audience_Type__c,
            'Audience type label should be Default Filter'
        );
        System.assertEquals(
            'Extole_Share_Link__c',
            log.Target_Field__c,
            'Target field should be stored'
        );
    }

    @IsTest
    static void testStartBackfillDateAudienceStoresDate() {
        Id logId = ExtoleBackfillController.startBackfill(
            'Contact',
            'date',
            '2025-01-01',
            null,
            'Extole_Share_Link__c',
            'my-program',
            'My Program'
        );

        Extole_Backfill_Log__c log = [
            SELECT Audience_Type__c, Audience_Criteria__c, Program_Label__c
            FROM Extole_Backfill_Log__c
            WHERE Id = :logId
        ];
        System.assertEquals(
            'Date Filter',
            log.Audience_Type__c,
            'Audience type should be Date Filter'
        );
        System.assert(
            log.Audience_Criteria__c.contains('2025-01-01'),
            'Criteria should contain the date'
        );
        // startBackfill prefers programName ("My Program") over the raw programLabel
        // key ("my-program") when both are supplied — programName is the friendlier value.
        System.assertEquals(
            'My Program',
            log.Program_Label__c,
            'Program label should prefer programName over the raw key'
        );
    }

    @IsTest
    static void testStartBackfillDefaultAudienceLeadDescribesFilter() {
        Id logId = ExtoleBackfillController.startBackfill(
            'Lead',
            'default',
            null,
            null,
            'Extole_Share_Link__c',
            '',
            ''
        );

        Extole_Backfill_Log__c log = [
            SELECT Audience_Criteria__c
            FROM Extole_Backfill_Log__c
            WHERE Id = :logId
        ];
        System.assertEquals(
            'Unconverted leads with email',
            log.Audience_Criteria__c
        );
    }

    @IsTest
    static void testStartBackfillReportAudienceStoresReportId() {
        Id logId = ExtoleBackfillController.startBackfill(
            'Lead',
            'report',
            null,
            '00O000000000000',
            'Extole_Share_Link__c',
            '',
            ''
        );

        Extole_Backfill_Log__c log = [
            SELECT Audience_Type__c, Audience_Criteria__c
            FROM Extole_Backfill_Log__c
            WHERE Id = :logId
        ];
        System.assertEquals(
            'Report',
            log.Audience_Type__c,
            'Audience type should be Report'
        );
        System.assertEquals(
            '00O000000000000',
            log.Audience_Criteria__c,
            'Criteria should be the report ID'
        );
    }

    // ─── getLastBackfillRun ───────────────────────────────────────────────────

    @IsTest
    static void testGetLastBackfillRunNullWhenEmpty() {
        Extole_Backfill_Log__c result = ExtoleBackfillController.getLastBackfillRun();
        System.assertEquals(
            null,
            result,
            'Should return null when no logs exist'
        );
    }

    @IsTest
    static void testGetLastBackfillRunReturnsMostRecent() {
        insert new List<Extole_Backfill_Log__c>{
            new Extole_Backfill_Log__c(
                Object_Type__c = 'Contact',
                Status__c = 'COMPLETED',
                Started_At__c = DateTime.now().addHours(-2),
                Target_Field__c = 'f'
            ),
            new Extole_Backfill_Log__c(
                Object_Type__c = 'Lead',
                Status__c = 'FAILED',
                Started_At__c = DateTime.now(),
                Target_Field__c = 'f'
            )
        };
        List<Extole_Backfill_Log__c> all = [
            SELECT Id
            FROM Extole_Backfill_Log__c
            ORDER BY Started_At__c DESC
        ];
        Extole_Backfill_Log__c result = ExtoleBackfillController.getLastBackfillRun();
        System.assertEquals(
            all[0].Id,
            result.Id,
            'Should return the most recently started run'
        );
    }

    // ─── getBackfillLogs ──────────────────────────────────────────────────────

    @IsTest
    static void testGetBackfillLogsEmpty() {
        System.assertEquals(
            0,
            ExtoleBackfillController.getBackfillLogs().size(),
            'Should return empty list when no logs'
        );
    }

    @IsTest
    static void testGetBackfillLogsReturnsAll() {
        insert new List<Extole_Backfill_Log__c>{
            new Extole_Backfill_Log__c(
                Object_Type__c = 'Contact',
                Status__c = 'COMPLETED',
                Started_At__c = DateTime.now().addHours(-1),
                Target_Field__c = 'f'
            ),
            new Extole_Backfill_Log__c(
                Object_Type__c = 'Lead',
                Status__c = 'FAILED',
                Started_At__c = DateTime.now().addHours(-2),
                Target_Field__c = 'f'
            )
        };
        System.assertEquals(
            2,
            ExtoleBackfillController.getBackfillLogs().size(),
            'Should return 2 logs'
        );
    }

    // ─── clearBackfillLogs ────────────────────────────────────────────────────

    @IsTest
    static void testClearBackfillLogsDeletesAll() {
        insert new List<Extole_Backfill_Log__c>{
            new Extole_Backfill_Log__c(
                Object_Type__c = 'Contact',
                Status__c = 'COMPLETED',
                Started_At__c = DateTime.now(),
                Target_Field__c = 'f'
            ),
            new Extole_Backfill_Log__c(
                Object_Type__c = 'Lead',
                Status__c = 'FAILED',
                Started_At__c = DateTime.now(),
                Target_Field__c = 'f'
            )
        };
        ExtoleBackfillController.clearBackfillLogs();
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Extole_Backfill_Log__c],
            'All logs should be deleted'
        );
    }
}
