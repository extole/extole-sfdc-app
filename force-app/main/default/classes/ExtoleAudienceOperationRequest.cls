@NamespaceAccessible
public class ExtoleAudienceOperationRequest {
    public static final String TYPE_ADD     = 'ADD';
    public static final String TYPE_REMOVE  = 'REMOVE';
    public static final String TYPE_REPLACE = 'REPLACE';

    private String       audienceId;
    private String       operationType;
    private List<String> emails;
    private List<String> tags;

    public ExtoleAudienceOperationRequest(String audienceId, String operationType) {
        this.audienceId    = audienceId;
        this.operationType = operationType;
        this.emails        = new List<String>();
    }

    public ExtoleAudienceOperationRequest withEmails(List<String> emails) {
        this.emails = emails == null ? new List<String>() : emails;
        return this;
    }

    public ExtoleAudienceOperationRequest withTags(List<String> tags) {
        this.tags = tags;
        return this;
    }

    public HttpRequest build(ExtoleConfig config) {
        if (String.isBlank(audienceId)) {
            throw new ExtoleApiException(0, 'ExtoleAudienceOperationRequest: audienceId is required');
        }
        if (String.isBlank(operationType)) {
            throw new ExtoleApiException(0, 'ExtoleAudienceOperationRequest: operationType is required');
        }
        if (operationType != TYPE_ADD && operationType != TYPE_REMOVE && operationType != TYPE_REPLACE) {
            throw new ExtoleApiException(0, 'ExtoleAudienceOperationRequest: unsupported operationType ' + operationType);
        }

        List<Object> members = new List<Object>();
        for (String email : emails) {
            if (String.isBlank(email)) continue;
            members.add(new Map<String, Object>{ 'email' => email });
        }

        Map<String, Object> body = new Map<String, Object>{
            'type'        => operationType,
            'data_source' => new Map<String, Object>{
                'type'             => 'PERSON_LIST',
                'audience_members' => members
            }
        };
        if (tags != null && !tags.isEmpty()) body.put('tags', tags);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.AUDIENCES_PATH + '/'
            + EncodingUtil.urlEncode(audienceId, 'UTF-8') + '/operations');
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
