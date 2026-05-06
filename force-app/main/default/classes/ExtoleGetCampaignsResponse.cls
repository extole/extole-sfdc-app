@NamespaceAccessible
public class ExtoleGetCampaignsResponse {
    public List<ExtoleCampaign> campaigns { get; private set; }

    public static ExtoleGetCampaignsResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        ExtoleGetCampaignsResponse resp = new ExtoleGetCampaignsResponse();
        resp.campaigns = new List<ExtoleCampaign>();
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.getBody());
        for (Object item : parsed) {
            resp.campaigns.add(ExtoleCampaign.fromMap((Map<String, Object>) item));
        }
        return resp;
    }
}
