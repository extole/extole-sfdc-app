// Check if the spike flow was created
Integer cnt = [SELECT COUNT() FROM FlowDefinitionView WHERE ApiName = 'Extole_Spike_Test_Flow'];
System.debug('SPIKE_A_FLOW_CHECK: Flow count = ' + cnt);
