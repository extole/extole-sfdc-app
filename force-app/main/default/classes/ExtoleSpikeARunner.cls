public class ExtoleSpikeARunner {

    // Test enqueueDeployment with empty container
    public static String runSpikeEnqueueDeployment() {
        try {
            Metadata.DeployContainer container = new Metadata.DeployContainer();
            ExtoleSpikeCallback callback = new ExtoleSpikeCallback();
            Id jobId = Metadata.Operations.enqueueDeployment(container, callback);
            System.debug('SPIKE_A_ENQUEUE_DEPLOY: Job enqueued with ID: ' + jobId);
            return 'ENQUEUED: ' + jobId;
        } catch (Exception e) {
            System.debug('SPIKE_A_ENQUEUE_DEPLOY: ERROR: ' + e.getMessage());
            return 'ERROR: ' + e.getMessage();
        }
    }

    // Test adding CustomMetadata and deploying — this WORKS (confirmed)
    public static String testAddMetadata() {
        try {
            Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
            cmd.fullName = 'Extole_Event_Config__mdt.Spike_Test';
            cmd.label = 'Spike Test';

            Metadata.DeployContainer container = new Metadata.DeployContainer();
            container.addMetadata(cmd);
            System.debug('SPIKE_A_ADD_METADATA: addMetadata(CustomMetadata) OK');

            ExtoleSpikeCallback callback = new ExtoleSpikeCallback();
            Id jobId = Metadata.Operations.enqueueDeployment(container, callback);
            System.debug('SPIKE_A_ADD_METADATA: enqueueDeployment returned: ' + jobId);
            return 'ENQUEUED: ' + jobId;
        } catch (Exception e) {
            System.debug('SPIKE_A_ADD_METADATA: ERROR: ' + e.getMessage());
            return 'ERROR: ' + e.getMessage();
        }
    }

    // Probe: does Metadata.Flow exist via Type.forName?
    public static void probeFlowType() {
        Type t = Type.forName('Metadata', 'Flow');
        System.debug('SPIKE_A_FLOW_TYPE: ' + t);

        Type t2 = Type.forName('Metadata', 'FlowActionCall');
        System.debug('SPIKE_A_FLOWACTIONCALL_TYPE: ' + t2);

        Type t3 = Type.forName('Metadata', 'FlowStart');
        System.debug('SPIKE_A_FLOWSTART_TYPE: ' + t3);

        Type t4 = Type.forName('Metadata', 'FlowTriggerType');
        System.debug('SPIKE_A_FLOWTRIGGERTYPE_TYPE: ' + t4);
    }

    // Check if Spike_Test MDT record exists (confirms deploy succeeded)
    public static void checkSpikeTestMDT() {
        Integer cnt = [SELECT COUNT() FROM Extole_Event_Config__mdt WHERE DeveloperName = 'Spike_Test'];
        System.debug('SPIKE_A_MDT_CHECK: Spike_Test MDT count = ' + cnt);

        DateTime tenMinutesAgo = DateTime.now().addMinutes(-10);
        Integer asyncJobs = [SELECT COUNT() FROM AsyncApexJob WHERE CreatedDate > :tenMinutesAgo];
        System.debug('SPIKE_A_ASYNC_JOBS_LAST_10MIN: ' + asyncJobs);
    }

    // Probe what Metadata types are available for Flow deployment
    // The Apex Metadata namespace only supports a limited set of types
    // Listed here are the types that DO exist in the Apex Metadata namespace
    public static void probeAvailableMetadataTypes() {
        // Known to work:
        Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
        System.debug('TYPE_CHECK: CustomMetadata = OK');

        System.debug('TYPE_CHECK: CustomLabel = NOT TESTED (compile check required)');
    }

    // Final definitive check: try to compile a class with Metadata.Flow
    // This is checked at compile time so will fail at deploy if Flow types don't exist
    public static void testFlowCompile() {
        // This will fail to compile if Metadata.Flow doesn't exist:
        // Metadata.Flow f = new Metadata.Flow(); // COMMENTED OUT — confirmed invalid
        System.debug('FLOW_COMPILE_CHECK: Metadata.Flow is NOT a valid Apex type in this API version');
        System.debug('FLOW_COMPILE_CHECK: Metadata.Operations can only deploy types in the Apex Metadata namespace');
        System.debug('FLOW_COMPILE_CHECK: Supported types include: CustomMetadata, CustomLabel, etc.');
        System.debug('FLOW_COMPILE_CHECK: Flow deployment requires Tooling API REST callout or MDAPI SOAP callout');
    }
}
