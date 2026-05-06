@NamespaceAccessible
public class ExtoleGetRewardsRequest {
    private String personId;

    public ExtoleGetRewardsRequest(String personId) {
        this.personId = personId;
    }

    public HttpRequest build(ExtoleConfig config) {
        if (String.isBlank(personId)) {
            throw new IllegalArgumentException('personId is required');
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.PEOPLE_PATH
            + '/' + personId + ExtoleConstants.REWARDS_PATH);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
