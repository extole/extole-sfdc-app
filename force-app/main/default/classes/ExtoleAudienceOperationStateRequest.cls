@NamespaceAccessible
public class ExtoleAudienceOperationStateRequest {
    private String audienceId;
    private String operationId;

    public ExtoleAudienceOperationStateRequest(String audienceId, String operationId) {
        this.audienceId  = audienceId;
        this.operationId = operationId;
    }

    public HttpRequest build(ExtoleConfig config) {
        if (String.isBlank(audienceId)) {
            throw new ExtoleApiException(0, 'ExtoleAudienceOperationStateRequest: audienceId is required');
        }
        if (String.isBlank(operationId)) {
            throw new ExtoleApiException(0, 'ExtoleAudienceOperationStateRequest: operationId is required');
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.AUDIENCES_PATH + '/'
            + EncodingUtil.urlEncode(audienceId, 'UTF-8') + '/operations/'
            + EncodingUtil.urlEncode(operationId, 'UTF-8') + '/state');
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
