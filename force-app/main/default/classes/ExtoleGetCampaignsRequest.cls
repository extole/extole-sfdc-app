@NamespaceAccessible
public class ExtoleGetCampaignsRequest {
    private String state;

    public ExtoleGetCampaignsRequest() {
        this.state = 'LIVE';
    }

    public ExtoleGetCampaignsRequest withState(String state) {
        this.state = state;
        return this;
    }

    public HttpRequest build(ExtoleConfig config) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.CAMPAIGNS_PATH + '?state=' + EncodingUtil.urlEncode(state, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
