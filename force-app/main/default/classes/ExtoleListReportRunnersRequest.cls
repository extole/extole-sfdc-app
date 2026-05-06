@NamespaceAccessible
public class ExtoleListReportRunnersRequest {
    private String type;

    public ExtoleListReportRunnersRequest() {
        this.type = 'SCHEDULED';
    }

    public ExtoleListReportRunnersRequest withType(String type) {
        this.type = type;
        return this;
    }

    public HttpRequest build(ExtoleConfig config) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.REPORT_RUNNERS_PATH + '?type=' + EncodingUtil.urlEncode(type, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
