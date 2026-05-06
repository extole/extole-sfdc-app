@NamespaceAccessible
public class ExtoleApiException extends Exception {
    public Integer httpStatus   { get; private set; }
    public String  responseBody { get; private set; }

    public ExtoleApiException(Integer httpStatus, String responseBody) {
        this.httpStatus   = httpStatus;
        this.responseBody = responseBody;
        this.setMessage('Extole API error HTTP ' + httpStatus + ': ' + responseBody);
    }
}
