@NamespaceAccessible
public class ExtoleCreateAudienceRequest {
    private String       name;
    private Boolean      enabled;
    private List<String> tags;

    public ExtoleCreateAudienceRequest(String name) {
        this.name = name;
        this.enabled = true;
    }

    public ExtoleCreateAudienceRequest withEnabled(Boolean enabled) {
        this.enabled = enabled;
        return this;
    }

    public ExtoleCreateAudienceRequest withTags(List<String> tags) {
        this.tags = tags;
        return this;
    }

    public HttpRequest build(ExtoleConfig config) {
        if (String.isBlank(name)) {
            throw new ExtoleApiException(0, 'ExtoleCreateAudienceRequest: name is required');
        }
        Map<String, Object> body = new Map<String, Object>{
            'name'    => name,
            'enabled' => enabled == null ? true : enabled
        };
        if (tags != null && !tags.isEmpty()) body.put('tags', tags);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.AUDIENCES_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setBody(JSON.serialize(body));
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
