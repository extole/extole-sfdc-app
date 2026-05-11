@NamespaceAccessible
public class ExtoleGetAudienceResponse {
    public ExtoleAudience audience { get; private set; }

    public static ExtoleGetAudienceResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        ExtoleGetAudienceResponse resp = new ExtoleGetAudienceResponse();
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        resp.audience = ExtoleAudience.fromMap(parsed);
        return resp;
    }
}
