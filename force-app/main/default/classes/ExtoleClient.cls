@NamespaceAccessible
public class ExtoleClient {
    public HttpResponse send(ExtoleConfig config, HttpRequest req) {
        Http http = new Http();
        return http.send(req);
    }
}
