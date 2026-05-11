@NamespaceAccessible
public class ExtoleGetAudienceRequest {
    private String audienceId;

    public ExtoleGetAudienceRequest(String audienceId) {
        this.audienceId = audienceId;
    }

    public HttpRequest build(ExtoleConfig config) {
        if (String.isBlank(audienceId)) {
            throw new ExtoleApiException(0, 'ExtoleGetAudienceRequest: audienceId is required');
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.AUDIENCES_PATH + '/'
            + EncodingUtil.urlEncode(audienceId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
