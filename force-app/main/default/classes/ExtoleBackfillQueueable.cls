/**
 * ExtoleBackfillQueueable
 *
 * For each record: look up the person in Extole by email (creating them if
 * they don't exist), then create a shareable to obtain the share link, and
 * write it back to the target SFDC field.
 *
 * API flow per person (up to 3 callouts):
 *   GET  /v5/persons?identity_key_value={email}
 *   POST /v5/persons                              (only if person not found)
 *   POST /v5/persons/{id}/shareables              (returns link)
 *   GET  /v5/persons/{id}/shareables              (only if label already taken)
 *
 * Chunk size is 25 to stay well within the 90-callout-per-execution limit.
 *
 * audienceType values:
 *   'default' — built-in filter (Closed Won contacts / unconverted leads); cursor-based, unlimited scale
 *   'date'    — all records with email created on/after selectedDate; cursor-based, unlimited scale
 *   'report'  — IDs loaded via Analytics REST API; capped at 2,000 rows
 */
public class ExtoleBackfillQueueable implements Queueable, Database.AllowsCallouts {

    private static final Integer CHUNK_SIZE = 25;

    private Id     logId;
    private String objectType;   // 'Contact' or 'Lead'
    private String audienceType; // 'default', 'date', or 'report'
    private String selectedDate; // YYYY-MM-DD, used when audienceType == 'date'
    private String reportId;
    private String targetField;
    private String programLabel;
    private Id     cursor;       // last processed Id for cursor-based pagination
    private List<Id> reportIds;
    private Integer  reportOffset;

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
        this.logId        = logId;
        this.objectType   = objectType;
        this.audienceType = audienceType;
        this.selectedDate = selectedDate;
        this.reportId     = reportId;
        this.targetField  = targetField;
        this.programLabel = programLabel;
        this.cursor       = cursor;
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
        this.logId         = logId;
        this.objectType    = objectType;
        this.audienceType  = 'report';
        this.targetField   = targetField;
        this.programLabel  = programLabel;
        this.reportIds     = reportIds;
        this.reportOffset  = reportOffset;
    }

    public void execute(QueueableContext ctx) {
        List<SObject> chunk;

        if (audienceType == 'report') {
            if (reportIds == null) {
                reportIds    = loadReportIds(reportId);
                reportOffset = 0;
            }
            if (reportIds == null || reportIds.isEmpty()) {
                finalize(0, 0, null);
                return;
            }
            Integer endIdx = Math.min(reportOffset + CHUNK_SIZE, reportIds.size());
            List<Id> page = new List<Id>();
            for (Integer i = reportOffset; i < endIdx; i++) page.add(reportIds[i]);
            chunk = queryRecords(page);
        } else {
            chunk = queryNextCursorChunk();
        }

        if (chunk == null || chunk.isEmpty()) {
            finalize(0, 0, null);
            return;
        }

        Integer successCount = 0;
        Integer errorCount   = 0;
        List<Map<String, String>> errors = new List<Map<String, String>>();
        List<SObject> toUpdate = new List<SObject>();

        for (SObject r : chunk) {
            String email = (String) r.get('Email');
            if (String.isBlank(email)) {
                errorCount++;
                errors.add(new Map<String, String>{
                    'id' => (String) r.get('Id'), 'name' => (String) r.get('Name'), 'error' => 'No email address'
                });
                continue;
            }

            String shareLink = resolveShareLink(email);
            if (shareLink == null) {
                errorCount++;
                errors.add(new Map<String, String>{
                    'id' => (String) r.get('Id'), 'name' => (String) r.get('Name'), 'error' => 'Could not obtain share link from Extole'
                });
                continue;
            }

            SObject updated = objectType == 'Contact'
                ? (SObject) new Contact(Id = (Id) r.get('Id'))
                : (SObject) new Lead(Id = (Id) r.get('Id'));
            updated.put(targetField, shareLink);
            toUpdate.add(updated);
            successCount++;
        }

        // Single bulk DML after all callouts
        if (!toUpdate.isEmpty()) {
            try {
                update toUpdate;
            } catch (Exception e) {
                System.debug('ExtoleBackfillQueueable: bulk update failed – ' + e.getMessage());
                errorCount   += toUpdate.size();
                successCount -= toUpdate.size();
            }
        }

        updateLogProgress(successCount, errorCount, errors);

        if (audienceType == 'report') {
            Integer nextOffset = reportOffset + CHUNK_SIZE;
            if (nextOffset < reportIds.size()) {
                System.enqueueJob(new ExtoleBackfillQueueable(
                    logId, objectType, targetField, programLabel, reportIds, nextOffset
                ));
            } else {
                finalize(successCount, errorCount, errors);
            }
        } else {
            if (chunk.size() == CHUNK_SIZE) {
                Id newCursor = (Id) chunk[chunk.size() - 1].get('Id');
                System.enqueueJob(new ExtoleBackfillQueueable(
                    logId, objectType, audienceType, selectedDate, reportId, targetField, programLabel, newCursor
                ));
            } else {
                finalize(successCount, errorCount, errors);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Extole API — person lookup + shareable creation
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Resolves the share link for a person by email.
     * 1. Look up person by identity_key_value (email).
     * 2. Create person if not found.
     * 3. Create shareable → returns link.
     * 4. If label already taken, fetch existing shareables and return matching link.
     */
    private String resolveShareLink(String email) {
        String personId = lookupOrCreatePerson(email);
        if (personId == null) return null;
        return createOrGetShareable(personId);
    }

    private static final ExtoleConfig EXTOLE_CONFIG = new ExtoleConfig('Extole_API');
    private static final ExtoleClient EXTOLE_CLIENT = new ExtoleClient();

    private String lookupOrCreatePerson(String email) {
        try {
            HttpResponse res = EXTOLE_CLIENT.send(EXTOLE_CONFIG,
                ExtoleGetPersonRequest.byEmail(email).build(EXTOLE_CONFIG));
            ExtoleGetPersonResponse lookup = ExtoleGetPersonResponse.fromResponse(res);
            if (lookup.person != null) return lookup.person.id;

            // Person not found — create
            HttpRequest createReq = new HttpRequest();
            createReq.setEndpoint('callout:Extole_API' + ExtoleConstants.PEOPLE_PATH);
            createReq.setMethod('POST');
            createReq.setHeader('Content-Type', 'application/json');
            createReq.setBody(JSON.serialize(new Map<String, Object>{
                'identity_key_value' => email
            }));
            createReq.setTimeout(30000);
            HttpResponse createRes = EXTOLE_CLIENT.send(EXTOLE_CONFIG, createReq);

            if (createRes.getStatusCode() >= 200 && createRes.getStatusCode() < 300) {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(createRes.getBody());
                return (String) body.get('id');
            }
            return null;
        } catch (Exception e) {
            System.debug('ExtoleBackfillQueueable.lookupOrCreatePerson: ' + e.getMessage());
            return null;
        }
    }

    private String createOrGetShareable(String personId) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Extole_API/v5/persons/' + personId + '/shareables');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(new Map<String, Object>{
                'label' => String.isNotBlank(programLabel) ? programLabel : 'extole-sfdc-app'
            }));
            req.setTimeout(30000);
            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                return (String) body.get('link');
            }

            // Shareable label already exists — fetch and return the existing one
            Map<String, Object> errBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String code = (String) errBody.get('code');
            if (code == 'shareable_key_taken') {
                return fetchExistingShareable(personId);
            }
            return null;
        } catch (Exception e) {
            System.debug('ExtoleBackfillQueueable.createOrGetShareable: ' + e.getMessage());
            return null;
        }
    }

    private String fetchExistingShareable(String personId) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Extole_API/v5/persons/' + personId + '/shareables');
            req.setMethod('GET');
            req.setTimeout(30000);
            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() != 200) return null;

            List<Object> shareables = (List<Object>) JSON.deserializeUntyped(res.getBody());
            String label = String.isNotBlank(programLabel) ? programLabel : 'extole-sfdc-app';
            for (Object raw : shareables) {
                Map<String, Object> s = (Map<String, Object>) raw;
                if (label == (String) s.get('label')) return (String) s.get('link');
            }
            // Return first available if label not matched
            if (!shareables.isEmpty()) {
                return (String) ((Map<String, Object>) shareables[0]).get('link');
            }
            return null;
        } catch (Exception e) {
            System.debug('ExtoleBackfillQueueable.fetchExistingShareable: ' + e.getMessage());
            return null;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SOQL helpers
    // ─────────────────────────────────────────────────────────────────────────

    private List<SObject> queryNextCursorChunk() {
        try {
            if (audienceType == 'date' && String.isNotBlank(selectedDate)) {
                Date dateFilter = Date.valueOf(selectedDate);
                String soql = 'SELECT Id, Name, Email FROM ' + objectType
                    + ' WHERE Email != null AND CreatedDate >= :dateFilter'
                    + (objectType == 'Lead' ? ' AND IsConverted = false' : '')
                    + (cursor != null ? ' AND Id > \'' + cursor + '\'' : '')
                    + ' ORDER BY Id ASC LIMIT ' + CHUNK_SIZE;
                return Database.query(soql);
            }

            // Default filter
            List<String> filters = new List<String>{ 'Email != null' };
            if (objectType == 'Contact') {
                filters.add('Id IN (SELECT ContactId FROM Opportunity WHERE StageName = \'Closed Won\' AND ContactId != null)');
            } else {
                filters.add('IsConverted = false');
            }
            if (cursor != null) filters.add('Id > \'' + cursor + '\'');

            String soql = 'SELECT Id, Name, Email FROM ' + objectType
                + ' WHERE ' + String.join(filters, ' AND ')
                + ' ORDER BY Id ASC LIMIT ' + CHUNK_SIZE;
            return Database.query(soql);
        } catch (Exception e) {
            System.debug('ExtoleBackfillQueueable.queryNextCursorChunk: ' + e.getMessage());
            return new List<SObject>();
        }
    }

    private List<SObject> queryRecords(List<Id> ids) {
        try {
            return Database.query(
                'SELECT Id, Name, Email FROM ' + objectType + ' WHERE Id IN :ids ORDER BY Id ASC'
            );
        } catch (Exception e) {
            System.debug('ExtoleBackfillQueueable.queryRecords: ' + e.getMessage());
            return new List<SObject>();
        }
    }

    /**
     * Fetch report rows via the Analytics REST API rather than the Reports Apex namespace,
     * which avoids Reports.ReportDataRow type availability issues across org configurations.
     */
    private List<Id> loadReportIds(String rptId) {
        List<Id> ids = new List<Id>();
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(URL.getOrgDomainUrl().toExternalForm()
                + '/services/data/v59.0/analytics/reports/' + rptId + '?includeDetails=true');
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setTimeout(30000);
            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() != 200) {
                markFailed('Analytics API error: HTTP ' + res.getStatusCode());
                return ids;
            }

            Map<String, Object> body     = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> factMap  = (Map<String, Object>) body.get('factMap');
            if (factMap == null) return ids;
            Map<String, Object> allRows  = (Map<String, Object>) factMap.get('T!T');
            if (allRows == null) return ids;
            List<Object> rows = (List<Object>) allRows.get('rows');
            if (rows == null) return ids;

            for (Object rowObj : rows) {
                Map<String, Object> row       = (Map<String, Object>) rowObj;
                List<Object>        dataCells = (List<Object>) row.get('dataCells');
                if (dataCells == null || dataCells.isEmpty()) continue;
                Map<String, Object> firstCell = (Map<String, Object>) dataCells[0];
                Object val = firstCell.get('value');
                if (val != null) {
                    try { ids.add((Id) String.valueOf(val)); } catch (Exception ignore) {}
                }
            }
        } catch (Exception e) {
            System.debug('ExtoleBackfillQueueable.loadReportIds: ' + e.getMessage());
            markFailed('Report load failed: ' + e.getMessage());
        }
        return ids;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Log helpers
    // ─────────────────────────────────────────────────────────────────────────

    private void updateLogProgress(Integer successes, Integer errors, List<Map<String, String>> errorDetails) {
        try {
            Extole_Backfill_Log__c log = [
                SELECT Id, Success_Count__c, Error_Count__c, Error_Detail__c
                FROM Extole_Backfill_Log__c WHERE Id = :logId LIMIT 1
            ];
            log.Success_Count__c = (log.Success_Count__c != null ? (Integer) log.Success_Count__c : 0) + successes;
            log.Error_Count__c   = (log.Error_Count__c   != null ? (Integer) log.Error_Count__c   : 0) + errors;

            if (!errorDetails.isEmpty()) {
                String existing = log.Error_Detail__c != null ? log.Error_Detail__c : '[]';
                List<Object> existingErrors = (List<Object>) JSON.deserializeUntyped(existing);
                for (Map<String, String> e : errorDetails) existingErrors.add(e);
                String serialized = JSON.serialize(existingErrors);
                log.Error_Detail__c = serialized.length() > 30000
                    ? serialized.substring(0, 30000) + '...'
                    : serialized;
            }
            update log;
        } catch (Exception e) {
            System.debug('ExtoleBackfillQueueable.updateLogProgress: ' + e.getMessage());
        }
    }

    private void finalize(Integer finalSuccesses, Integer finalErrors, List<Map<String, String>> errorDetails) {
        try {
            Extole_Backfill_Log__c log = [
                SELECT Id, Success_Count__c, Error_Count__c
                FROM Extole_Backfill_Log__c WHERE Id = :logId LIMIT 1
            ];
            Integer totalSuccess = (log.Success_Count__c != null ? (Integer) log.Success_Count__c : 0) + finalSuccesses;
            Integer totalErrors  = (log.Error_Count__c   != null ? (Integer) log.Error_Count__c   : 0) + finalErrors;
            log.Success_Count__c = totalSuccess;
            log.Error_Count__c   = totalErrors;
            log.Total_Count__c   = totalSuccess + totalErrors;
            log.Completed_At__c  = DateTime.now();
            log.Status__c        = totalErrors > 0
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
                Id              = logId,
                Status__c       = 'FAILED',
                Completed_At__c = DateTime.now(),
                Error_Detail__c = JSON.serialize(new List<Object>{
                    new Map<String, String>{ 'error' => reason }
                })
            );
        } catch (Exception e) {
            System.debug('ExtoleBackfillQueueable.markFailed: ' + e.getMessage());
        }
    }
}
