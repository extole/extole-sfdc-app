@NamespaceAccessible
public class ExtoleListProgramsRequest {
    public HttpRequest build(ExtoleConfig config) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.CAMPAIGNS_SUMMARY_PATH);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
