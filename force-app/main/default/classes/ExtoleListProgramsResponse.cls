@NamespaceAccessible
public class ExtoleListProgramsResponse {
    public List<ExtoleProgram> programs { get; private set; }

    public static ExtoleListProgramsResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        ExtoleListProgramsResponse resp = new ExtoleListProgramsResponse();
        resp.programs = new List<ExtoleProgram>();
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(res.getBody());
        for (Object item : parsed) {
            resp.programs.add(ExtoleProgram.fromMap((Map<String, Object>) item));
        }
        return resp;
    }
}
