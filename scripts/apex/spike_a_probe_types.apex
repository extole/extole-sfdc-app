// Probe what Metadata Flow types exist in anonymous apex
try {
    // Try creating a Metadata.Flow object
    Metadata.Flow f = new Metadata.Flow();
    System.debug('PROBE: Metadata.Flow created OK - fullName=' + f.fullName);
} catch (Exception e) {
    System.debug('PROBE: Metadata.Flow FAILED: ' + e.getMessage());
}

try {
    Metadata.FlowStart s = new Metadata.FlowStart();
    System.debug('PROBE: Metadata.FlowStart created OK');
} catch (Exception e) {
    System.debug('PROBE: Metadata.FlowStart FAILED: ' + e.getMessage());
}

try {
    Metadata.FlowConnector c = new Metadata.FlowConnector();
    System.debug('PROBE: Metadata.FlowConnector created OK');
} catch (Exception e) {
    System.debug('PROBE: Metadata.FlowConnector FAILED: ' + e.getMessage());
}

try {
    Metadata.DeployContainer dc = new Metadata.DeployContainer();
    System.debug('PROBE: Metadata.DeployContainer created OK');
} catch (Exception e) {
    System.debug('PROBE: Metadata.DeployContainer FAILED: ' + e.getMessage());
}
