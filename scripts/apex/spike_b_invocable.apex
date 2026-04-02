// SPIKE B: Validate that ExtoleUniversalHandler.HandlerInput works
// and that invoke() handles the wrapper correctly

try {
    ExtoleUniversalHandler.HandlerInput input = new ExtoleUniversalHandler.HandlerInput();
    input.configKey = 'spike_test_config';
    input.recordId = '001000000000001AAA'; // fake ID

    List<ExtoleUniversalHandler.HandlerInput> inputs = new List<ExtoleUniversalHandler.HandlerInput>{ input };
    ExtoleUniversalHandler.invoke(inputs);

    System.debug('SPIKE_B: invoke() completed without error');
    System.debug('SPIKE_B: RESULT = SUCCESS - wrapper class and InvocableMethod work correctly');
} catch (Exception e) {
    System.debug('SPIKE_B: ERROR: ' + e.getMessage());
}
