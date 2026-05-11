@NamespaceAccessible
public class ExtoleListAudiencesResponse {
    public List<ExtoleAudience> audiences { get; private set; }

    public static ExtoleListAudiencesResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        ExtoleListAudiencesResponse resp = new ExtoleListAudiencesResponse();
        resp.audiences = new List<ExtoleAudience>();
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.getBody());
        for (Object item : parsed) {
            resp.audiences.add(ExtoleAudience.fromMap((Map<String, Object>) item));
        }
        return resp;
    }

    public ExtoleAudience findByName(String name) {
        if (audiences == null || String.isBlank(name)) return null;
        for (ExtoleAudience a : audiences) {
            if (name.equals(a.name)) return a;
        }
        return null;
    }
}
