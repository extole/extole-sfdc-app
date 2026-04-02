// PROBE 2: Deploy a Record-Triggered Flow via Metadata API
// Run AFTER probe_1 so the class Extole_Handler_probe_lead_created exists.
// Run with: sf apex run --file scripts/apex/probe_2_deploy_flow.apex -o extole-sandbox
//
// Success: prints "Probe 2 PASSED — flow deployed: ..." in debug log
// Failure: prints exception message

String configKey     = 'probe_lead_created_v2';
String triggerObject = 'Lead';
String triggerType   = 'CREATED';
String triggerField  = null;
String triggerValue  = null;
String apexClassName = 'Extole_Handler_probe_lead_created'; // class already exists from probe 1

try {
    String flowName = ExtoleMetadataService.deployFlow(
        configKey, triggerObject, triggerType,
        triggerField, triggerValue, apexClassName
    );
    System.debug('Probe 2 PASSED — flow deployed: ' + flowName);
} catch (Exception e) {
    System.debug('Probe 2 FAILED — ' + e.getTypeName() + ': ' + e.getMessage());
}
