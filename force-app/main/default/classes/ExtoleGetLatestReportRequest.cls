@NamespaceAccessible
public class ExtoleGetLatestReportRequest {
    private String runnerId;

    public ExtoleGetLatestReportRequest(String runnerId) {
        this.runnerId = runnerId;
    }

    public HttpRequest build(ExtoleConfig config) {
        if (String.isBlank(runnerId)) {
            throw new IllegalArgumentException('runnerId is required');
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.REPORT_V4_PATH
            + '?runner_id=' + EncodingUtil.urlEncode(runnerId, 'UTF-8') + '&limit=1');
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
