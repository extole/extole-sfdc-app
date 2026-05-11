/**
 * GET /v4/reports/{report_id} — fetch the current status of an on-demand report.
 * Polled until status is DONE (or terminal failure) before downloading.
 */
@NamespaceAccessible
public class ExtoleGetReportStatusRequest {
    private String reportId;

    public ExtoleGetReportStatusRequest(String reportId) {
        this.reportId = reportId;
    }

    public HttpRequest build(ExtoleConfig config) {
        if (String.isBlank(reportId)) {
            throw new ExtoleApiException(0, 'ExtoleGetReportStatusRequest: reportId is required');
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.REPORT_V4_PATH
            + '/' + EncodingUtil.urlEncode(reportId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
