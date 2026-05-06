@NamespaceAccessible
public with sharing class ExtoleApiSetupController {

    @AuraEnabled
    public static Map<String, Object> testConnection() {
        try {
            ExtoleConfig config = new ExtoleConfig('Extole_API');
            HttpResponse raw = new ExtoleClient().send(config,
                new ExtoleListReportRunnersRequest().build(config));
            if (raw.getStatusCode() >= 200 && raw.getStatusCode() < 300) {
                return new Map<String, Object>{ 'success' => true, 'message' => 'Connected successfully.' };
            }
            return new Map<String, Object>{
                'success' => false,
                'message' => 'HTTP ' + raw.getStatusCode() + ': ' + raw.getBody()
            };
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'message' => e.getMessage() };
        }
    }
}
