@NamespaceAccessible
public class ExtoleEventFireResponse {
    public String eventId { get; private set; }

    public static ExtoleEventFireResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        ExtoleEventFireResponse resp = new ExtoleEventFireResponse();
        resp.eventId = (String) parsed.get('id');
        return resp;
    }
}
