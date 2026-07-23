public class ExtoleBackfillQueueable implements Queueable, Database.AllowsCallouts {
    private static final Integer CHUNK_SIZE = 25;

    private Id logId;
    private String objectType;
    private String audienceType;
    private String selectedDate;
    private String reportId;
    private String targetField;
    private String programLabel;
    private Id cursor;
    private List<Id> reportIds;
    private Integer reportOffset;

    public ExtoleBackfillQueueable(
        Id logId,
        String objectType,
        String audienceType,
        String selectedDate,
        String reportId,
        String targetField,
        String programLabel,
        Id cursor
    ) {
        this.logId = logId;
        this.objectType = objectType;
        this.audienceType = audienceType;
        this.selectedDate = selectedDate;
        this.reportId = reportId;
        this.targetField = targetField;
        this.programLabel = programLabel;
        this.cursor = cursor;
        this.reportOffset = 0;
    }

    private ExtoleBackfillQueueable(
        Id logId,
        String objectType,
        String targetField,
        String programLabel,
        List<Id> reportIds,
        Integer reportOffset
    ) {
        this.logId = logId;
        this.objectType = objectType;
        this.audienceType = 'report';
        this.targetField = targetField;
        this.programLabel = programLabel;
        this.reportIds = reportIds;
        this.reportOffset = reportOffset;
    }

    public void execute(QueueableContext context) {
        List<SObject> chunk;

        if (audienceType == 'report') {
            Boolean isFirstLoad = reportIds == null;
            if (isFirstLoad) {
                reportIds = loadReportIds(reportId);
                reportOffset = 0;
            }
            if (isFirstLoad && reportIds == null) {
                return;
            }
            if (reportIds.isEmpty()) {
                finalize();
                return;
            }
            Integer endIdx = Math.min(
                reportOffset + CHUNK_SIZE,
                reportIds.size()
            );
            List<Id> page = new List<Id>();
            for (Integer i = reportOffset; i < endIdx; i++)
                page.add(reportIds[i]);
            chunk = queryRecords(page);
        } else {
            chunk = queryNextCursorChunk();
        }

        if (chunk == null || chunk.isEmpty()) {
            finalize();
            return;
        }

        Integer successCount = 0;
        Integer errorCount = 0;
        List<Map<String, String>> errors = new List<Map<String, String>>();
        List<SObject> toUpdate = new List<SObject>();

        for (SObject r : chunk) {
            String email = (String) r.get('Email');
            if (String.isBlank(email)) {
                errorCount++;
                errors.add(
                    new Map<String, String>{
                        'id' => (String) r.get('Id'),
                        'name' => (String) r.get('Name'),
                        'error' => 'No email address'
                    }
                );
                continue;
            }

            String shareLink = resolveShareLink(email);
            if (shareLink == null) {
                errorCount++;
                errors.add(
                    new Map<String, String>{
                        'id' => (String) r.get('Id'),
                        'name' => (String) r.get('Name'),
                        'error' => 'Could not obtain share link from Extole'
                    }
                );
                continue;
            }

            SObject updated = objectType == 'Contact'
                ? (SObject) new Contact(Id = (Id) r.get('Id'))
                : (SObject) new Lead(Id = (Id) r.get('Id'));
            updated.put(targetField, shareLink);
            toUpdate.add(updated);
            successCount++;
        }

        if (!toUpdate.isEmpty()) {
            try {
                update toUpdate;
            } catch (Exception e) {
                System.debug(
                    'ExtoleBackfillQueueable: bulk update failed – ' +
                    e.getMessage()
                );
                errorCount += toUpdate.size();
                successCount -= toUpdate.size();
            }
        }

        updateLogProgress(successCount, errorCount, errors);

        if (audienceType == 'report') {
            Integer nextOffset = reportOffset + CHUNK_SIZE;
            if (nextOffset < reportIds.size()) {
                System.enqueueJob(
                    new ExtoleBackfillQueueable(
                        logId,
                        objectType,
                        targetField,
                        programLabel,
                        reportIds,
                        nextOffset
                    )
                );
            } else {
                finalize();
            }
        } else {
            if (chunk.size() == CHUNK_SIZE) {
                Id newCursor = (Id) chunk[chunk.size() - 1].get('Id');
                System.enqueueJob(
                    new ExtoleBackfillQueueable(
                        logId,
                        objectType,
                        audienceType,
                        selectedDate,
                        reportId,
                        targetField,
                        programLabel,
                        newCursor
                    )
                );
            } else {
                finalize();
            }
        }
    }

    private String resolveShareLink(String email) {
        String personId = lookupOrCreatePerson(email);
        if (personId == null)
            return null;
        return createOrGetShareable(personId);
    }

    private static final ExtoleConfig EXTOLE_CONFIG = new ExtoleConfig(
        'Extole_API'
    );
    private static final ExtoleClient EXTOLE_CLIENT = new ExtoleClient();

    private String lookupOrCreatePerson(String email) {
        try {
            HttpResponse response = EXTOLE_CLIENT.send(
                EXTOLE_CONFIG,
                ExtoleGetPersonRequest.byEmail(email).build(EXTOLE_CONFIG)
            );
            ExtoleGetPersonResponse lookup = ExtoleGetPersonResponse.fromResponse(
                response
            );
            if (lookup.person != null)
                return lookup.person.id;

            HttpRequest createRequest = new HttpRequest();
            createRequest.setEndpoint(
                'callout:Extole_API' + ExtoleConstants.PEOPLE_PATH
            );
            createRequest.setMethod('POST');
            createRequest.setHeader('Content-Type', 'application/json');
            createRequest.setBody(
                JSON.serialize(
                    new Map<String, Object>{ 'identity_key_value' => email }
                )
            );
            createRequest.setTimeout(30000);
            HttpResponse createResponse = EXTOLE_CLIENT.send(
                EXTOLE_CONFIG,
                createRequest
            );

            if (
                createResponse.getStatusCode() >= 200 &&
                createResponse.getStatusCode() < 300
            ) {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
                    createResponse.getBody()
                );
                return (String) body.get('id');
            }
            return null;
        } catch (Exception e) {
            System.debug(
                'ExtoleBackfillQueueable.lookupOrCreatePerson: ' +
                e.getMessage()
            );
            return null;
        }
    }

    private String createOrGetShareable(String personId) {
        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(
                'callout:Extole_API/v5/persons/' + personId + '/shareables'
            );
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setBody(
                JSON.serialize(
                    new Map<String, Object>{
                        'label' => String.isNotBlank(programLabel)
                            ? programLabel
                            : 'extole-sfdc-app'
                    }
                )
            );
            request.setTimeout(30000);
            HttpResponse response = new Http().send(request);

            if (
                response.getStatusCode() >= 200 &&
                response.getStatusCode() < 300
            ) {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
                    response.getBody()
                );
                return (String) body.get('link');
            }

            Map<String, Object> errBody = (Map<String, Object>) JSON.deserializeUntyped(
                response.getBody()
            );
            String code = (String) errBody.get('code');
            if (code == 'shareable_key_taken') {
                return fetchExistingShareable(personId);
            }
            return null;
        } catch (Exception e) {
            System.debug(
                'ExtoleBackfillQueueable.createOrGetShareable: ' +
                e.getMessage()
            );
            return null;
        }
    }

    private String fetchExistingShareable(String personId) {
        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(
                'callout:Extole_API/v5/persons/' + personId + '/shareables'
            );
            request.setMethod('GET');
            request.setTimeout(30000);
            HttpResponse response = new Http().send(request);

            if (response.getStatusCode() != 200)
                return null;

            List<Object> shareables = (List<Object>) JSON.deserializeUntyped(
                response.getBody()
            );
            String label = String.isNotBlank(programLabel)
                ? programLabel
                : 'extole-sfdc-app';
            for (Object raw : shareables) {
                Map<String, Object> s = (Map<String, Object>) raw;
                if (label == (String) s.get('label'))
                    return (String) s.get('link');
            }
            if (!shareables.isEmpty()) {
                return (String) ((Map<String, Object>) shareables[0])
                    .get('link');
            }
            return null;
        } catch (Exception e) {
            System.debug(
                'ExtoleBackfillQueueable.fetchExistingShareable: ' +
                e.getMessage()
            );
            return null;
        }
    }

    private List<SObject> queryNextCursorChunk() {
        try {
            if (audienceType == 'date' && String.isNotBlank(selectedDate)) {
                Date dateFilter = Date.valueOf(selectedDate);
                String soql =
                    'SELECT Id, Name, Email FROM ' +
                    objectType +
                    ' WHERE Email != null AND CreatedDate >= :dateFilter' +
                    (objectType == 'Lead' ? ' AND IsConverted = false' : '') +
                    (cursor != null ? ' AND Id > \'' + cursor + '\'' : '') +
                    ' ORDER BY Id ASC LIMIT ' +
                    CHUNK_SIZE;
                return Database.query(soql);
            }

            List<String> filters = new List<String>{ 'Email != null' };
            if (objectType == 'Contact') {
                filters.add(
                    'Id IN (SELECT ContactId FROM Opportunity WHERE StageName = \'Closed Won\' AND ContactId != null)'
                );
            } else {
                filters.add('IsConverted = false');
            }
            if (cursor != null)
                filters.add('Id > \'' + cursor + '\'');

            String soql =
                'SELECT Id, Name, Email FROM ' +
                objectType +
                ' WHERE ' +
                String.join(filters, ' AND ') +
                ' ORDER BY Id ASC LIMIT ' +
                CHUNK_SIZE;
            return Database.query(soql);
        } catch (Exception e) {
            System.debug(
                'ExtoleBackfillQueueable.queryNextCursorChunk: ' +
                e.getMessage()
            );
            return new List<SObject>();
        }
    }

    private List<SObject> queryRecords(List<Id> ids) {
        try {
            return Database.query(
                'SELECT Id, Name, Email FROM ' +
                    objectType +
                    ' WHERE Id IN :ids ORDER BY Id ASC'
            );
        } catch (Exception e) {
            System.debug(
                'ExtoleBackfillQueueable.queryRecords: ' + e.getMessage()
            );
            return new List<SObject>();
        }
    }

    private List<Id> loadReportIds(String reportId) {
        List<Id> ids = new List<Id>();
        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(
                URL.getOrgDomainUrl().toExternalForm() +
                    '/services/data/v59.0/analytics/reports/' +
                    reportId +
                    '?includeDetails=true'
            );
            request.setMethod('GET');
            request.setHeader(
                'Authorization',
                'Bearer ' + UserInfo.getSessionId()
            );
            request.setTimeout(30000);
            HttpResponse response = new Http().send(request);

            if (response.getStatusCode() != 200) {
                markFailed(
                    'Analytics API error: HTTP ' + response.getStatusCode()
                );
                return null;
            }

            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
                response.getBody()
            );
            Map<String, Object> factMap = (Map<String, Object>) body.get(
                'factMap'
            );
            if (factMap == null)
                return ids;
            Map<String, Object> allRows = (Map<String, Object>) factMap.get(
                'T!T'
            );
            if (allRows == null)
                return ids;
            List<Object> rows = (List<Object>) allRows.get('rows');
            if (rows == null)
                return ids;

            for (Object rowObj : rows) {
                Map<String, Object> row = (Map<String, Object>) rowObj;
                List<Object> dataCells = (List<Object>) row.get('dataCells');
                if (dataCells == null || dataCells.isEmpty())
                    continue;
                Map<String, Object> firstCell = (Map<String, Object>) dataCells[0];
                Object value = firstCell.get('value');
                if (value != null) {
                    try {
                        ids.add((Id) String.valueOf(value));
                    } catch (Exception ignore) {
                    }
                }
            }
        } catch (Exception e) {
            System.debug(
                'ExtoleBackfillQueueable.loadReportIds: ' + e.getMessage()
            );
            markFailed('Report load failed: ' + e.getMessage());
            return null;
        }
        return ids;
    }

    private void updateLogProgress(
        Integer successes,
        Integer errors,
        List<Map<String, String>> errorDetails
    ) {
        try {
            Extole_Backfill_Log__c log = [
                SELECT Id, Success_Count__c, Error_Count__c, Error_Detail__c
                FROM Extole_Backfill_Log__c
                WHERE Id = :logId
                LIMIT 1
            ];
            log.Success_Count__c =
                (log.Success_Count__c != null
                    ? (Integer) log.Success_Count__c
                    : 0) + successes;
            log.Error_Count__c =
                (log.Error_Count__c != null
                    ? (Integer) log.Error_Count__c
                    : 0) + errors;

            if (!errorDetails.isEmpty()) {
                String existing = log.Error_Detail__c != null
                    ? log.Error_Detail__c
                    : '[]';
                List<Object> existingErrors = (List<Object>) JSON.deserializeUntyped(
                    existing
                );
                for (Map<String, String> e : errorDetails)
                    existingErrors.add(e);
                String serialized = JSON.serialize(existingErrors);
                log.Error_Detail__c = serialized.length() > 30000
                    ? serialized.substring(0, 30000) + '...'
                    : serialized;
            }
            update log;
        } catch (Exception e) {
            System.debug(
                'ExtoleBackfillQueueable.updateLogProgress: ' + e.getMessage()
            );
        }
    }

    private void finalize() {
        try {
            Extole_Backfill_Log__c log = [
                SELECT Id, Success_Count__c, Error_Count__c
                FROM Extole_Backfill_Log__c
                WHERE Id = :logId
                LIMIT 1
            ];
            Integer totalSuccess = log.Success_Count__c != null
                ? (Integer) log.Success_Count__c
                : 0;
            Integer totalErrors = log.Error_Count__c != null
                ? (Integer) log.Error_Count__c
                : 0;
            log.Success_Count__c = totalSuccess;
            log.Error_Count__c = totalErrors;
            log.Total_Count__c = totalSuccess + totalErrors;
            log.Completed_At__c = DateTime.now();
            log.Status__c = totalErrors > 0
                ? (totalSuccess > 0 ? 'COMPLETED_WITH_ERRORS' : 'FAILED')
                : 'COMPLETED';
            update log;
        } catch (Exception e) {
            System.debug('ExtoleBackfillQueueable.finalize: ' + e.getMessage());
        }
    }

    private void markFailed(String reason) {
        try {
            update new Extole_Backfill_Log__c(
                Id = logId,
                Status__c = 'FAILED',
                Completed_At__c = DateTime.now(),
                Error_Detail__c = JSON.serialize(
                    new List<Object>{
                        new Map<String, String>{ 'error' => reason }
                    }
                )
            );
        } catch (Exception e) {
            System.debug(
                'ExtoleBackfillQueueable.markFailed: ' + e.getMessage()
            );
        }
    }
}
