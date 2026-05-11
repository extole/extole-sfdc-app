@NamespaceAccessible
public class ExtoleCreateAudienceResponse {
    public ExtoleAudience audience { get; private set; }

    public static ExtoleCreateAudienceResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        ExtoleCreateAudienceResponse resp = new ExtoleCreateAudienceResponse();
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        resp.audience = ExtoleAudience.fromMap(parsed);
        return resp;
    }
}
