@NamespaceAccessible
public class ExtoleDownloadReportRequest {
    private String reportId;

    public ExtoleDownloadReportRequest(String reportId) {
        this.reportId = reportId;
    }

    public HttpRequest build(ExtoleConfig config) {
        if (String.isBlank(reportId)) {
            throw new IllegalArgumentException('reportId is required');
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.REPORT_V4_PATH
            + '/' + reportId + ExtoleConstants.REPORT_DOWNLOAD_PATH);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
