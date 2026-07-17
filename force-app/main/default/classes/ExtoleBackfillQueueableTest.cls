@IsTest
private class ExtoleBackfillQueueableTest {

    // ─── HTTP mocks ────────────────────────────────────────────────────────────

    // Person found → shareable created successfully
    private class HappyPathMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            String ep  = req.getEndpoint();
            String mth = req.getMethod();

            if (ep.contains('identity_key_value') && mth == 'GET') {
                res.setStatusCode(200);
                res.setBody('[{"id":"person-001","email":"test@extole-test.com"}]');
            } else if (ep.contains('/v5/persons/') && ep.endsWith('/shareables') && mth == 'POST') {
                res.setStatusCode(201);
                res.setBody('{"id":"share-001","link":"https://test.extole.com/s/happy","label":"extole-sfdc-app"}');
            } else {
                res.setStatusCode(404);
                res.setBody('{}');
            }
            return res;
        }
    }

    // Person not found → create person → create shareable
    private class PersonNotFoundMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            String ep  = req.getEndpoint();
            String mth = req.getMethod();

            if (ep.contains('identity_key_value') && mth == 'GET') {
                res.setStatusCode(200);
                res.setBody('[]');
            } else if (ep.contains('/v5/persons') && !ep.contains('/shareables') && mth == 'POST') {
                res.setStatusCode(201);
                res.setBody('{"id":"person-new","email":"new@extole-test.com"}');
            } else if (ep.contains('/v5/persons/') && ep.endsWith('/shareables') && mth == 'POST') {
                res.setStatusCode(201);
                res.setBody('{"id":"share-002","link":"https://test.extole.com/s/created","label":"extole-sfdc-app"}');
            } else {
                res.setStatusCode(404);
                res.setBody('{}');
            }
            return res;
        }
    }

    // Shareable label already taken → fetch existing
    private class LabelTakenMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            String ep  = req.getEndpoint();
            String mth = req.getMethod();

            if (ep.contains('identity_key_value') && mth == 'GET') {
                res.setStatusCode(200);
                res.setBody('[{"id":"person-001"}]');
            } else if (ep.endsWith('/shareables') && mth == 'POST') {
                res.setStatusCode(409);
                res.setBody('{"code":"shareable_key_taken","message":"Label already in use"}');
            } else if (ep.endsWith('/shareables') && mth == 'GET') {
                res.setStatusCode(200);
                res.setBody('[{"id":"share-existing","link":"https://test.extole.com/s/existing","label":"extole-sfdc-app"}]');
            } else {
                res.setStatusCode(404);
                res.setBody('{}');
            }
            return res;
        }
    }

    // All callouts return 500
    private class AllFailingMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Service unavailable"}');
            return res;
        }
    }

    // ─── Test data helpers ─────────────────────────────────────────────────────

    private static Extole_Backfill_Log__c makeLog(String objectType) {
        Extole_Backfill_Log__c log = new Extole_Backfill_Log__c(
            Object_Type__c       = objectType,
            Audience_Type__c     = 'Date Filter',
            Audience_Criteria__c = 'Test run',
            Target_Field__c      = 'Extole_Share_Link__c',
            Status__c            = 'IN_PROGRESS',
            Started_At__c        = DateTime.now()
        );
        insert log;
        return log;
    }

    private static String yesterday() {
        return String.valueOf(Date.today().addDays(-1));
    }

    // ─── Happy path: Contact, date filter, person found ───────────────────────

    @IsTest
    static void testDateFilterContactWritesShareLink() {
        Contact c = new Contact(FirstName = 'Happy', LastName = 'Contact', Email = 'happy@extole-test.com');
        insert c;

        Extole_Backfill_Log__c log = makeLog('Contact');

        Test.setMock(HttpCalloutMock.class, new HappyPathMock());
        Test.startTest();
        System.enqueueJob(new ExtoleBackfillQueueable(
            log.Id, 'Contact', 'date', yesterday(), null, 'Extole_Share_Link__c', '', null
        ));
        Test.stopTest();

        Extole_Backfill_Log__c result = [SELECT Status__c, Success_Count__c FROM Extole_Backfill_Log__c WHERE Id = :log.Id];
        System.assert(result.Status__c == 'COMPLETED' || result.Status__c == 'COMPLETED_WITH_ERRORS',
            'Log should be COMPLETED or COMPLETED_WITH_ERRORS');
        System.assert((Integer) result.Success_Count__c >= 1, 'Should have at least 1 success');

        Contact updated = [SELECT Extole_Share_Link__c FROM Contact WHERE Id = :c.Id];
        System.assertNotEquals(null, updated.Extole_Share_Link__c, 'Share link should be written to Contact');
        System.assert(updated.Extole_Share_Link__c.startsWith('https://'), 'Share link should be a URL');
    }

    // ─── Happy path: Lead, date filter ────────────────────────────────────────

    @IsTest
    static void testDateFilterLeadWritesShareLink() {
        Lead l = new Lead(FirstName = 'Happy', LastName = 'Lead', Email = 'happylead@extole-test.com', Company = 'Test Co');
        insert l;

        Extole_Backfill_Log__c log = makeLog('Lead');

        Test.setMock(HttpCalloutMock.class, new HappyPathMock());
        Test.startTest();
        System.enqueueJob(new ExtoleBackfillQueueable(
            log.Id, 'Lead', 'date', yesterday(), null, 'Extole_Share_Link__c', '', null
        ));
        Test.stopTest();

        Extole_Backfill_Log__c result = [SELECT Status__c, Success_Count__c FROM Extole_Backfill_Log__c WHERE Id = :log.Id];
        System.assert(result.Status__c == 'COMPLETED' || result.Status__c == 'COMPLETED_WITH_ERRORS',
            'Log should be COMPLETED or COMPLETED_WITH_ERRORS for Lead');
        System.assert((Integer) result.Success_Count__c >= 1, 'Should have at least 1 success for Lead');

        Lead updated = [SELECT Extole_Share_Link__c FROM Lead WHERE Id = :l.Id];
        System.assertNotEquals(null, updated.Extole_Share_Link__c, 'Share link should be written to Lead');
    }

    // ─── Person not found → create person → write link ────────────────────────

    @IsTest
    static void testPersonNotFoundCreatesAndWritesLink() {
        Contact c = new Contact(FirstName = 'New', LastName = 'Person', Email = 'newperson@extole-test.com');
        insert c;

        Extole_Backfill_Log__c log = makeLog('Contact');

        Test.setMock(HttpCalloutMock.class, new PersonNotFoundMock());
        Test.startTest();
        System.enqueueJob(new ExtoleBackfillQueueable(
            log.Id, 'Contact', 'date', yesterday(), null, 'Extole_Share_Link__c', '', null
        ));
        Test.stopTest();

        Extole_Backfill_Log__c result = [SELECT Status__c, Success_Count__c FROM Extole_Backfill_Log__c WHERE Id = :log.Id];
        System.assert(result.Status__c == 'COMPLETED' || result.Status__c == 'COMPLETED_WITH_ERRORS',
            'Log should be COMPLETED via create path');
        System.assert((Integer) result.Success_Count__c >= 1, 'Should succeed via person create path');

        Contact updated = [SELECT Extole_Share_Link__c FROM Contact WHERE Id = :c.Id];
        System.assertNotEquals(null, updated.Extole_Share_Link__c, 'Link should be written via create-person path');
        System.assertEquals('https://test.extole.com/s/created', updated.Extole_Share_Link__c);
    }

    // ─── Shareable label taken → fetch existing ────────────────────────────────

    @IsTest
    static void testLabelTakenFetchesExistingShareable() {
        Contact c = new Contact(FirstName = 'Taken', LastName = 'Label', Email = 'takenlabel@extole-test.com');
        insert c;

        Extole_Backfill_Log__c log = makeLog('Contact');

        Test.setMock(HttpCalloutMock.class, new LabelTakenMock());
        Test.startTest();
        System.enqueueJob(new ExtoleBackfillQueueable(
            log.Id, 'Contact', 'date', yesterday(), null, 'Extole_Share_Link__c', '', null
        ));
        Test.stopTest();

        Contact updated = [SELECT Extole_Share_Link__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals('https://test.extole.com/s/existing', updated.Extole_Share_Link__c,
            'Should use existing shareable link when label is taken');
    }

    // ─── API failure → records error, no write ────────────────────────────────

    @IsTest
    static void testApiFailureRecordsErrorInLog() {
        Contact c = new Contact(FirstName = 'Error', LastName = 'Test', Email = 'errortest@extole-test.com');
        insert c;

        Extole_Backfill_Log__c log = makeLog('Contact');

        Test.setMock(HttpCalloutMock.class, new AllFailingMock());
        Test.startTest();
        System.enqueueJob(new ExtoleBackfillQueueable(
            log.Id, 'Contact', 'date', yesterday(), null, 'Extole_Share_Link__c', '', null
        ));
        Test.stopTest();

        Extole_Backfill_Log__c result = [SELECT Status__c, Error_Count__c, Success_Count__c FROM Extole_Backfill_Log__c WHERE Id = :log.Id];
        System.assertEquals('FAILED', result.Status__c, 'Log should be FAILED when all API calls fail');
        System.assert((Integer) result.Error_Count__c >= 1, 'Should have at least 1 error');
        System.assertEquals(0, (Integer) (result.Success_Count__c != null ? result.Success_Count__c : 0), 'Should have 0 successes');

        Contact unchanged = [SELECT Extole_Share_Link__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(null, unchanged.Extole_Share_Link__c, 'Share link should not be written on API failure');
    }

    // ─── No matching records → COMPLETED with zero counts ────────────────────

    @IsTest
    static void testNoMatchingRecordsCompletesCleanly() {
        Extole_Backfill_Log__c log = makeLog('Contact');

        Test.setMock(HttpCalloutMock.class, new HappyPathMock());
        Test.startTest();
        System.enqueueJob(new ExtoleBackfillQueueable(
            log.Id, 'Contact', 'date', String.valueOf(Date.today().addDays(1)), null, 'Extole_Share_Link__c', '', null
        ));
        Test.stopTest();

        Extole_Backfill_Log__c result = [SELECT Status__c, Success_Count__c, Total_Count__c FROM Extole_Backfill_Log__c WHERE Id = :log.Id];
        System.assertEquals('COMPLETED', result.Status__c, 'Should be COMPLETED even with zero records');
        System.assertEquals(0, (Integer) (result.Success_Count__c != null ? result.Success_Count__c : 0), 'Success count should be 0');
        System.assertEquals(0, (Integer) (result.Total_Count__c   != null ? result.Total_Count__c   : 0), 'Total count should be 0');
    }

    // ─── COMPLETED_WITH_ERRORS when some succeed and some fail ────────────────

    @IsTest
    static void testMixedResultsCompletedWithErrors() {
        // One contact with email (will fail), verify log shows COMPLETED_WITH_ERRORS
        // We set up a "fail on second call" mock by tracking call count
        Contact c1 = new Contact(FirstName = 'Mix1', LastName = 'Test', Email = 'mix1@extole-test.com');
        Contact c2 = new Contact(FirstName = 'Mix2', LastName = 'Test', Email = 'mix2@extole-test.com');
        insert new List<Contact>{ c1, c2 };

        Extole_Backfill_Log__c log = makeLog('Contact');

        // Simulate: first contact lookup succeeds (happy), second person lookup fails → 1 success, 1 error
        Test.setMock(HttpCalloutMock.class, new MixedResultsMock());
        Test.startTest();
        System.enqueueJob(new ExtoleBackfillQueueable(
            log.Id, 'Contact', 'date', yesterday(), null, 'Extole_Share_Link__c', '', null
        ));
        Test.stopTest();

        Extole_Backfill_Log__c result = [SELECT Status__c, Success_Count__c, Error_Count__c FROM Extole_Backfill_Log__c WHERE Id = :log.Id];
        System.assertEquals('COMPLETED_WITH_ERRORS', result.Status__c, 'Should be COMPLETED_WITH_ERRORS when both succeed and fail');
        System.assert((Integer) result.Success_Count__c >= 1, 'Should have at least 1 success');
        System.assert((Integer) result.Error_Count__c   >= 1, 'Should have at least 1 error');
    }

    // Returns success for first person lookup, failure for second
    private class MixedResultsMock implements HttpCalloutMock {
        private Integer callCount = 0;

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            String ep  = req.getEndpoint();
            String mth = req.getMethod();

            if (ep.contains('identity_key_value') && mth == 'GET') {
                callCount++;
                if (callCount == 1) {
                    res.setStatusCode(200);
                    res.setBody('[{"id":"person-001"}]');
                } else {
                    // Second person lookup fails
                    res.setStatusCode(500);
                    res.setBody('{"error":"Service unavailable"}');
                }
            } else if (ep.endsWith('/shareables') && mth == 'POST') {
                res.setStatusCode(201);
                res.setBody('{"id":"share-001","link":"https://test.extole.com/s/first","label":"extole-sfdc-app"}');
            } else {
                res.setStatusCode(404);
                res.setBody('{}');
            }
            return res;
        }
    }

    // ─── Program label passed through ────────────────────────────────────────

    @IsTest
    static void testProgramLabelIsPassedToShareablesRequest() {
        Contact c = new Contact(FirstName = 'Program', LastName = 'Label', Email = 'program@extole-test.com');
        insert c;

        Extole_Backfill_Log__c log = makeLog('Contact');

        ProgramLabelCaptureMock captureMock = new ProgramLabelCaptureMock();
        Test.setMock(HttpCalloutMock.class, captureMock);
        Test.startTest();
        System.enqueueJob(new ExtoleBackfillQueueable(
            log.Id, 'Contact', 'date', yesterday(), null, 'Extole_Share_Link__c', 'my-referral-program', null
        ));
        Test.stopTest();

        System.assert(captureMock.capturedBody != null && captureMock.capturedBody.contains('my-referral-program'),
            'Program label should be included in the shareables POST body');
    }

    private class ProgramLabelCaptureMock implements HttpCalloutMock {
        public String capturedBody;

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            String ep  = req.getEndpoint();
            String mth = req.getMethod();

            if (ep.contains('identity_key_value')) {
                res.setStatusCode(200);
                res.setBody('[{"id":"person-001"}]');
            } else if (ep.endsWith('/shareables') && mth == 'POST') {
                capturedBody = req.getBody();
                res.setStatusCode(201);
                res.setBody('{"id":"share-001","link":"https://test.extole.com/s/prog","label":"my-referral-program"}');
            } else {
                res.setStatusCode(404);
                res.setBody('{}');
            }
            return res;
        }
    }
}
