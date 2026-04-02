// PROBE 1: Deploy a handler class via Tooling API
// Run with: sf apex run --file scripts/apex/probe_1_deploy_handler_class.apex -o extole-sandbox
//
// Success: prints "Probe 1 PASSED — class deployed, id=..." in debug log
// Failure: prints exception message explaining what went wrong

String configKey    = 'probe_lead_created';
Integer version     = 1;
String triggerObject = 'Lead';
String fields       = 'Id, Email, FirstName, LastName';
String eventName    = 'sfdc_lead_created';
String fieldMappingsJSON = '[{"extole_param":"email","sfdc_field":"Email","static_value":null},{"extole_param":"first_name","sfdc_field":"FirstName","static_value":null},{"extole_param":"last_name","sfdc_field":"LastName","static_value":null}]';

try {
    String classId = ExtoleToolingService.deployHandlerClass(
        configKey, version, triggerObject, fields, eventName, fieldMappingsJSON
    );
    System.debug('Probe 1 PASSED — class deployed, id=' + classId);
} catch (Exception e) {
    System.debug('Probe 1 FAILED — ' + e.getTypeName() + ': ' + e.getMessage());
}
