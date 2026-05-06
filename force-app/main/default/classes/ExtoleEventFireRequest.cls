@NamespaceAccessible
public class ExtoleEventFireRequest {
    public String              eventName { get; private set; }
    public Map<String, Object> data      { get; private set; }

    public ExtoleEventFireRequest(String eventName) {
        this.eventName = eventName;
        this.data = new Map<String, Object>();
    }

    public ExtoleEventFireRequest withData(String key, Object value) {
        this.data.put(key, value);
        return this;
    }

    public ExtoleEventFireRequest withDataMap(Map<String, Object> dataMap) {
        if (dataMap != null) this.data.putAll(dataMap);
        return this;
    }

    public HttpRequest build(ExtoleConfig config) {
        if (String.isBlank(eventName)) {
            throw new IllegalArgumentException('eventName is required');
        }
        Map<String, Object> body = new Map<String, Object>{
            'event_name' => eventName,
            'data'       => data
        };
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.EVENTS_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setBody(JSON.serialize(body));
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
