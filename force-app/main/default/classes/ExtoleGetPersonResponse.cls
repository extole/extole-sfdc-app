@NamespaceAccessible
public class ExtoleGetPersonResponse {
    public ExtolePerson person { get; private set; }

    public static ExtoleGetPersonResponse fromResponse(HttpResponse res) {
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ExtoleApiException(res.getStatusCode(), res.getBody());
        }
        ExtoleGetPersonResponse resp = new ExtoleGetPersonResponse();
        String body = res.getBody();
        if (String.isNotBlank(body) && body.startsWith('[')) {
            List<Object> persons = (List<Object>) JSON.deserializeUntyped(body);
            if (!persons.isEmpty()) {
                resp.person = ExtolePerson.fromMap((Map<String, Object>) persons[0]);
            }
        } else if (String.isNotBlank(body) && body.startsWith('{')) {
            resp.person = ExtolePerson.fromMap((Map<String, Object>) JSON.deserializeUntyped(body));
        }
        return resp;
    }
}
