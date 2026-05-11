/**
 * Wraps the POST /v4/reports response — returns an ExtoleReportInstance
 * with the new report's id and initial status (typically PENDING).
 */
@NamespaceAccessible
public class ExtoleCreateSummaryReportResponse {
    public ExtoleReportInstance reportInstance { get; private set; }

    public static ExtoleCreateSummaryReportResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        // Pluribus returns id/report_id inconsistently across endpoints. Normalise.
        if (parsed.get('report_id') == null && parsed.get('id') != null) {
            parsed.put('report_id', parsed.get('id'));
        }
        ExtoleCreateSummaryReportResponse resp = new ExtoleCreateSummaryReportResponse();
        resp.reportInstance = ExtoleReportInstance.fromMap(parsed);
        return resp;
    }
}
