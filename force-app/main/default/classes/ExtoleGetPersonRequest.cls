@NamespaceAccessible
public class ExtoleGetPersonRequest {
    private String email;
    private String personId;

    public static ExtoleGetPersonRequest byEmail(String email) {
        ExtoleGetPersonRequest r = new ExtoleGetPersonRequest();
        r.email = email;
        return r;
    }

    public static ExtoleGetPersonRequest byId(String personId) {
        ExtoleGetPersonRequest r = new ExtoleGetPersonRequest();
        r.personId = personId;
        return r;
    }

    public HttpRequest build(ExtoleConfig config) {
        if (String.isBlank(email) && String.isBlank(personId)) {
            throw new IllegalArgumentException('email or personId is required');
        }
        String endpoint;
        if (!String.isBlank(personId)) {
            endpoint = config.getEndpoint() + ExtoleConstants.PEOPLE_PATH + '/' + personId;
        } else {
            endpoint = config.getEndpoint() + ExtoleConstants.PEOPLE_PATH
                + '?identity_key_value=' + EncodingUtil.urlEncode(email, 'UTF-8');
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
