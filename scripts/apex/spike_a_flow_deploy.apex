// SPIKE A: Test deploying a Record-Triggered Flow via Metadata.Operations
// We deploy a minimal Lead-created flow that calls ExtoleUniversalHandler

try {
    // Build the action call node
    Metadata.FlowActionCall actionCall = new Metadata.FlowActionCall();
    actionCall.name = 'InvokeHandler';
    actionCall.label = 'Invoke Extole Handler';
    actionCall.locationX = 50;
    actionCall.locationY = 200;
    actionCall.actionType = Metadata.InvocableActionType.Apex;
    actionCall.actionName = 'ExtoleUniversalHandler';

    // Input: configKey = static constant 'spike_test'
    Metadata.FlowInputFieldAssignment configKeyParam = new Metadata.FlowInputFieldAssignment();
    configKeyParam.field = 'configKey';
    configKeyParam.value = new Metadata.FlowElementReferenceOrValue();
    configKeyParam.value.stringValue = 'spike_test';

    // Input: recordId = $Record.Id
    Metadata.FlowInputFieldAssignment recordIdParam = new Metadata.FlowInputFieldAssignment();
    recordIdParam.field = 'recordId';
    recordIdParam.value = new Metadata.FlowElementReferenceOrValue();
    recordIdParam.value.elementReference = '$Record.Id';

    // Note: FlowActionCall uses inputParameters not inputFieldAssignments for Apex actions
    Metadata.FlowActionCallInputParameter configKeyInput = new Metadata.FlowActionCallInputParameter();
    configKeyInput.name = 'configKey';
    configKeyInput.value = new Metadata.FlowElementReferenceOrValue();
    configKeyInput.value.stringValue = 'spike_test';

    Metadata.FlowActionCallInputParameter recordIdInput = new Metadata.FlowActionCallInputParameter();
    recordIdInput.name = 'recordId';
    recordIdInput.value = new Metadata.FlowElementReferenceOrValue();
    recordIdInput.value.elementReference = '$Record.Id';

    actionCall.inputParameters = new List<Metadata.FlowActionCallInputParameter>{ configKeyInput, recordIdInput };

    // Build the start node
    Metadata.FlowStart startNode = new Metadata.FlowStart();
    startNode.locationX = 50;
    startNode.locationY = 50;
    startNode.object_x = 'Lead';
    startNode.recordTriggerType = Metadata.RecordTriggerType.Create;
    startNode.triggerType = Metadata.FlowTriggerType.RecordAfterSave;
    Metadata.FlowConnector conn = new Metadata.FlowConnector();
    conn.targetReference = 'InvokeHandler';
    startNode.connector = conn;

    // Build the Flow
    Metadata.Flow flow = new Metadata.Flow();
    flow.fullName = 'Extole_Spike_Test_Flow';
    flow.label = 'Extole Spike Test Flow';
    flow.processType = 'AutoLaunchedFlow';
    flow.apiVersion = 59;
    flow.status = 'Active';
    flow.start = startNode;
    flow.actionCalls = new List<Metadata.FlowActionCall>{ actionCall };

    // Deploy
    Metadata.DeployContainer container = new Metadata.DeployContainer();
    container.addMetadata(flow);

    ExtoleSpikeCallback callback = new ExtoleSpikeCallback();
    Id jobId = Metadata.Operations.enqueueRetrieve(container, callback);
    System.debug('SPIKE_A: Job enqueued with ID: ' + jobId);

} catch (Exception e) {
    System.debug('SPIKE_A: COMPILE/RUNTIME ERROR: ' + e.getMessage());
    System.debug('SPIKE_A: Stack: ' + e.getStackTraceString());
}
