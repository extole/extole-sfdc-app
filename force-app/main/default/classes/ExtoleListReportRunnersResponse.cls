@NamespaceAccessible
public class ExtoleListReportRunnersResponse {
    public List<ExtoleReportRunner> runners { get; private set; }

    public static ExtoleListReportRunnersResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        ExtoleListReportRunnersResponse resp = new ExtoleListReportRunnersResponse();
        resp.runners = new List<ExtoleReportRunner>();
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.getBody());
        for (Object item : parsed) {
            resp.runners.add(ExtoleReportRunner.fromMap((Map<String, Object>) item));
        }
        return resp;
    }
}
