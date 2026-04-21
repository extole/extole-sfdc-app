// Test 22 — Bulk event dispatch (>100 records)
// Step 1 of 3: Save a Lead Created event config (must run before test_22_deploy.apex)
// Run: sf apex run --file scripts/tests/test_22_setup.apex --target-org <alias>

String configJson = JSON.serialize(new Map<String, Object>{
    'eventName'        => 'lead_created',
    'triggerObject'    => 'Lead',
    'triggerType'      => 'CREATED',
    'fieldMappingsJson'=> '[{"extole_param":"email","sfdc_field":"Email"},{"extole_param":"first_name","sfdc_field":"FirstName"},{"extole_param":"last_name","sfdc_field":"LastName"}]'
});
String configKey = ExtoleEventController.saveEventConfig(configJson);
System.debug('Saved config key: ' + configKey);
