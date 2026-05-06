@NamespaceAccessible
public class ExtoleGetLatestReportResponse {
    public ExtoleReportInstance instance { get; private set; }

    public static ExtoleGetLatestReportResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        ExtoleGetLatestReportResponse resp = new ExtoleGetLatestReportResponse();
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.getBody());
        if (!parsed.isEmpty()) {
            resp.instance = ExtoleReportInstance.fromMap((Map<String, Object>) parsed[0]);
        }
        return resp;
    }
}
