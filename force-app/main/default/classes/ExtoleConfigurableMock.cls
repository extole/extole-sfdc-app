@NamespaceAccessible
@IsTest
public class ExtoleConfigurableMock implements HttpCalloutMock {
    private List<MockEntry> entries = new List<MockEntry>();
    private Integer defaultStatus = 200;
    private String  defaultBody   = '{}';

    private class MockEntry {
        String  endpointSubstring;
        Integer statusCode;
        String  body;
        MockEntry(String s, Integer c, String b) {
            endpointSubstring = s; statusCode = c; body = b;
        }
    }

    public ExtoleConfigurableMock addPattern(String endpointSubstring, Integer statusCode, String body) {
        entries.add(new MockEntry(endpointSubstring, statusCode, body));
        return this;
    }

    public ExtoleConfigurableMock withDefault(Integer statusCode, String body) {
        defaultStatus = statusCode;
        defaultBody   = body;
        return this;
    }

    public HttpResponse respond(HttpRequest req) {
        String endpoint = req.getEndpoint();
        for (MockEntry entry : entries) {
            if (endpoint.contains(entry.endpointSubstring)) {
                return buildResponse(entry.statusCode, entry.body);
            }
        }
        return buildResponse(defaultStatus, defaultBody);
    }

    private static HttpResponse buildResponse(Integer statusCode, String body) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setBody(body);
        return res;
    }
}
