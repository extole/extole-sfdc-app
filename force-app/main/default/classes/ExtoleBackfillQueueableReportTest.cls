@IsTest
private class ExtoleBackfillQueueableReportTest {
    private static Extole_Backfill_Log__c makeLog(String objectType) {
        Extole_Backfill_Log__c log = new Extole_Backfill_Log__c(
            Object_Type__c = objectType,
            Audience_Type__c = 'Report',
            Audience_Criteria__c = 'Test report run',
            Target_Field__c = 'Extole_Share_Link__c',
            Status__c = 'IN_PROGRESS',
            Started_At__c = DateTime.now()
        );
        insert log;
        return log;
    }

    // Handles both the Analytics REST report endpoint and the Extole API calls
    // in the same mock, since a single HttpCalloutMock covers every callout in the test.
    private class ReportAndExtoleMock implements HttpCalloutMock {
        String reportBody;
        Integer reportStatus;
        ReportAndExtoleMock(Integer reportStatus, String reportBody) {
            this.reportStatus = reportStatus;
            this.reportBody = reportBody;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint();
            String mth = req.getMethod();

            if (ep.contains('/services/data/v59.0/analytics/reports/')) {
                res.setStatusCode(reportStatus);
                res.setBody(reportBody);
                return res;
            }
            if (ep.contains('identity_key_value') && mth == 'GET') {
                res.setStatusCode(200);
                res.setBody(
                    '[{"id":"person-001","email":"test@extole-test.com"}]'
                );
                return res;
            }
            if (
                ep.contains('/v5/persons/') &&
                ep.endsWith('/shareables') &&
                mth == 'POST'
            ) {
                res.setStatusCode(201);
                res.setBody(
                    '{"id":"share-001","link":"https://test.extole.com/s/report","label":"extole-sfdc-app"}'
                );
                return res;
            }
            res.setStatusCode(404);
            res.setBody('{}');
            return res;
        }
    }

    private static String analyticsReportJson(List<Id> ids) {
        List<String> rows = new List<String>();
        for (Id recId : ids) {
            rows.add('{"dataCells":[{"value":"' + recId + '"}]}');
        }
        return '{"factMap":{"T!T":{"rows":[' + String.join(rows, ',') + ']}}}';
    }

    @IsTest
    static void testReportAudience_happyPathBackfillsMatchingRecords() {
        Contact c1 = new Contact(LastName = 'One', Email = 'one@example.com');
        Contact c2 = new Contact(LastName = 'Two', Email = 'two@example.com');
        insert new List<Contact>{ c1, c2 };

        Extole_Backfill_Log__c log = makeLog('Contact');

        Test.setMock(
            HttpCalloutMock.class,
            new ReportAndExtoleMock(
                200,
                analyticsReportJson(new List<Id>{ c1.Id, c2.Id })
            )
        );

        Test.startTest();
        new ExtoleBackfillQueueable(
                log.Id,
                'Contact',
                'report',
                null,
                'rpt123',
                'Extole_Share_Link__c',
                'my-program',
                null
            )
            .execute(null);
        Test.stopTest();

        Extole_Backfill_Log__c updated = [
            SELECT Success_Count__c, Error_Count__c, Status__c
            FROM Extole_Backfill_Log__c
            WHERE Id = :log.Id
        ];
        System.assertEquals(2, updated.Success_Count__c);
        System.assertEquals(0, updated.Error_Count__c);
        System.assertEquals('COMPLETED', updated.Status__c);

        List<Contact> updatedContacts = [
            SELECT Extole_Share_Link__c
            FROM Contact
            WHERE Id IN (:c1.Id, :c2.Id)
        ];
        for (Contact c : updatedContacts) {
            System.assertEquals(
                'https://test.extole.com/s/report',
                c.Extole_Share_Link__c
            );
        }
    }

    @IsTest
    static void testReportAudience_emptyReportFinalizesCleanly() {
        Extole_Backfill_Log__c log = makeLog('Contact');

        Test.setMock(
            HttpCalloutMock.class,
            new ReportAndExtoleMock(200, '{"factMap":{"T!T":{"rows":[]}}}')
        );

        Test.startTest();
        new ExtoleBackfillQueueable(
                log.Id,
                'Contact',
                'report',
                null,
                'rpt_empty',
                'Extole_Share_Link__c',
                null,
                null
            )
            .execute(null);
        Test.stopTest();

        Extole_Backfill_Log__c updated = [
            SELECT Status__c, Total_Count__c
            FROM Extole_Backfill_Log__c
            WHERE Id = :log.Id
        ];
        System.assertEquals('COMPLETED', updated.Status__c);
        System.assertEquals(0, updated.Total_Count__c);
    }

    @IsTest
    static void testReportAudience_analyticsApiFailureMarksFailed() {
        Extole_Backfill_Log__c log = makeLog('Contact');

        Test.setMock(
            HttpCalloutMock.class,
            new ReportAndExtoleMock(500, '{"error":"boom"}')
        );

        Test.startTest();
        new ExtoleBackfillQueueable(
                log.Id,
                'Contact',
                'report',
                null,
                'rpt_fail',
                'Extole_Share_Link__c',
                null,
                null
            )
            .execute(null);
        Test.stopTest();

        Extole_Backfill_Log__c updated = [
            SELECT Status__c, Error_Detail__c
            FROM Extole_Backfill_Log__c
            WHERE Id = :log.Id
        ];
        System.assertEquals('FAILED', updated.Status__c);
        System.assert(updated.Error_Detail__c.contains('Analytics API error'));
    }

    @IsTest
    static void testReportAudience_leadObjectType() {
        Lead l1 = new Lead(
            LastName = 'Test',
            Company = 'Acme',
            Email = 'lead1@example.com'
        );
        insert l1;

        Extole_Backfill_Log__c log = makeLog('Lead');

        Test.setMock(
            HttpCalloutMock.class,
            new ReportAndExtoleMock(
                200,
                analyticsReportJson(new List<Id>{ l1.Id })
            )
        );

        Test.startTest();
        new ExtoleBackfillQueueable(
                log.Id,
                'Lead',
                'report',
                null,
                'rpt_lead',
                'Extole_Share_Link__c',
                null,
                null
            )
            .execute(null);
        Test.stopTest();

        Lead updated = [
            SELECT Extole_Share_Link__c
            FROM Lead
            WHERE Id = :l1.Id
        ];
        System.assertEquals(
            'https://test.extole.com/s/report',
            updated.Extole_Share_Link__c
        );
    }
}
