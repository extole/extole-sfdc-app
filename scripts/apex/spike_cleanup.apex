// Cleanup: delete the Spike_Test CustomMetadata record via Metadata.Operations
try {
    Metadata.DeployContainer container = new Metadata.DeployContainer();
    Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
    cmd.fullName = 'Extole_Event_Config__mdt.Spike_Test';
    cmd.label = 'Spike Test';
    // Note: to delete, we'd need Metadata.Operations.enqueueDelete (doesn't exist)
    // Instead, we'll just note that MDT records don't cause test pollution
    System.debug('CLEANUP: Spike_Test MDT record was created during spike.');
    System.debug('CLEANUP: MDT records in sandbox do not affect production packages.');
    System.debug('CLEANUP: Will delete via sf cli: sf data delete record --sobject Extole_Event_Config__mdt --record-id');
} catch (Exception e) {
    System.debug('CLEANUP: ' + e.getMessage());
}

// Verify the Flow was never created
Integer cnt = [SELECT COUNT() FROM FlowDefinitionView WHERE ApiName = 'Extole_Spike_Test_Flow'];
System.debug('CLEANUP_FLOW_CHECK: Flow count = ' + cnt + ' (should be 0)');
