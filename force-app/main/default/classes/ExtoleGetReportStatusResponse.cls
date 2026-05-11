/**
 * Wraps the GET /v4/reports/{id} status response.
 */
@NamespaceAccessible
public class ExtoleGetReportStatusResponse {
    public ExtoleReportInstance reportInstance { get; private set; }

    public static ExtoleGetReportStatusResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (parsed.get('report_id') == null && parsed.get('id') != null) {
            parsed.put('report_id', parsed.get('id'));
        }
        ExtoleGetReportStatusResponse resp = new ExtoleGetReportStatusResponse();
        resp.reportInstance = ExtoleReportInstance.fromMap(parsed);
        return resp;
    }

    public Boolean isComplete() {
        return reportInstance != null
            && ('DONE'.equals(reportInstance.status) || 'COMPLETED'.equals(reportInstance.status));
    }

    public Boolean isFailed() {
        return reportInstance != null
            && ('FAILED'.equals(reportInstance.status) || 'CANCELLED'.equals(reportInstance.status));
    }

    public Boolean isTerminal() {
        return isComplete() || isFailed();
    }
}
