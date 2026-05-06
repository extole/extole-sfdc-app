@NamespaceAccessible
public class ExtoleGetRewardsResponse {
    public List<ExtoleReward> rewards { get; private set; }

    public static ExtoleGetRewardsResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        ExtoleGetRewardsResponse resp = new ExtoleGetRewardsResponse();
        resp.rewards = new List<ExtoleReward>();
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.getBody());
        for (Object item : parsed) {
            resp.rewards.add(ExtoleReward.fromMap((Map<String, Object>) item));
        }
        return resp;
    }
}
