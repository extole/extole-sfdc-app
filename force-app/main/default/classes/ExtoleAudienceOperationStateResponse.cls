@NamespaceAccessible
public class ExtoleAudienceOperationStateResponse {
    public ExtoleAudienceOperation operation { get; private set; }

    public static ExtoleAudienceOperationStateResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        ExtoleAudienceOperationStateResponse resp = new ExtoleAudienceOperationStateResponse();
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        resp.operation = ExtoleAudienceOperation.fromMap(parsed);
        return resp;
    }

    public Boolean isTerminal() {
        return operation != null && (operation.state == 'READY' || operation.state == 'FAILED');
    }

    public Boolean isSuccess() {
        return operation != null && operation.state == 'READY';
    }
}
