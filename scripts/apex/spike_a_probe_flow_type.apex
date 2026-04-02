// Probe: does Metadata.Flow exist via Type.forName?
ExtoleSpikeARunner.probeFlowType();

// Also test adding CustomMetadata to container and deploying
String result = ExtoleSpikeARunner.testAddMetadata();
System.debug('ADD_METADATA_RESULT: ' + result);
