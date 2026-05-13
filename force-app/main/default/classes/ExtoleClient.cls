@NamespaceAccessible
public class ExtoleClient {

    @TestVisible
    private static final String APP_TYPE = 'extole-sfdc-app';

    public HttpResponse send(ExtoleConfig config, HttpRequest req) {
        req.setEndpoint(withAppType(req.getEndpoint()));
        Http http = new Http();
        return http.send(req);
    }

    @TestVisible
    private static String withAppType(String endpoint) {
        if (String.isBlank(endpoint)) return endpoint;
        // Skip if already present (defensive — no existing call site adds it,
        // but downstream code may inject app_type into POST event payloads
        // separately, and we shouldn't double up if someone adds it here later)
        if (endpoint.contains('app_type=')) return endpoint;
        String sep = endpoint.contains('?') ? '&' : '?';
        return endpoint + sep + 'app_type=' + APP_TYPE;
    }
}
