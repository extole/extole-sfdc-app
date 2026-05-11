@NamespaceAccessible
public class ExtoleAudienceOperationResponse {
    public ExtoleAudienceOperation operation { get; private set; }

    public static ExtoleAudienceOperationResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        ExtoleAudienceOperationResponse resp = new ExtoleAudienceOperationResponse();
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        resp.operation = ExtoleAudienceOperation.fromMap(parsed);
        return resp;
    }
}
