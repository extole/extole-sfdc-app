// Test enqueueDeployment compiles and runs (empty container = no-op deploy)
String result = ExtoleSpikeARunner.runSpikeEnqueueDeployment();
System.debug('SPIKE_A_ENQUEUE_RESULT: ' + result);
