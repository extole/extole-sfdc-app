@NamespaceAccessible
public class ExtoleDownloadReportResponse {
    public List<Map<String, Object>> rows    { get; private set; }
    public String                    rawBody { get; private set; }

    public static ExtoleDownloadReportResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        ExtoleDownloadReportResponse resp = new ExtoleDownloadReportResponse();
        resp.rawBody = res.getBody();
        resp.rows = new List<Map<String, Object>>();
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.getBody());
        for (Object item : parsed) {
            resp.rows.add((Map<String, Object>) item);
        }
        return resp;
    }
}
