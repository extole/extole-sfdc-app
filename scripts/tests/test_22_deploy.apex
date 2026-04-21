// Test 22 — Bulk event dispatch (>100 records)
// Step 2 of 3: Deploy the Lead Created event config (run after test_22_setup.apex)
// Run: sf apex run --file scripts/tests/test_22_deploy.apex --target-org <alias>

String configJson = JSON.serialize(new Map<String, Object>{
    'configKey'        => 'Lead_lead_created',
    'eventName'        => 'lead_created',
    'triggerObject'    => 'Lead',
    'triggerType'      => 'CREATED',
    'fieldMappingsJson'=> '[{"extole_param":"email","sfdc_field":"Email"},{"extole_param":"first_name","sfdc_field":"FirstName"},{"extole_param":"last_name","sfdc_field":"LastName"}]'
});
ExtoleEventController.deployEventConfig(configJson);
System.debug('Deployed Lead_lead_created — Flow active');
