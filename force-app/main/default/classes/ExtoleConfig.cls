@NamespaceAccessible
public class ExtoleConfig {
    public String  namedCredential { get; private set; }
    public String  baseUrl         { get; private set; }
    public String  bearerToken     { get; private set; }
    public Integer timeoutMs       { get; private set; }

    private static final Integer DEFAULT_TIMEOUT_MS = 30000;

    public ExtoleConfig(String namedCredential) {
        this.namedCredential = namedCredential;
        this.timeoutMs = DEFAULT_TIMEOUT_MS;
    }

    public ExtoleConfig(String baseUrl, String bearerToken) {
        this.baseUrl     = baseUrl;
        this.bearerToken = bearerToken;
        this.timeoutMs   = DEFAULT_TIMEOUT_MS;
    }

    public ExtoleConfig withTimeout(Integer timeoutMs) {
        this.timeoutMs = timeoutMs;
        return this;
    }

    public String getEndpoint() {
        return isNamedCredentialMode() ? 'callout:' + namedCredential : baseUrl;
    }

    public String getAuthHeader() {
        return isNamedCredentialMode() ? null : 'Bearer ' + bearerToken;
    }

    public Boolean isNamedCredentialMode() {
        return namedCredential != null;
    }
}
