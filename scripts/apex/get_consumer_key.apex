// Retrieve the Consumer Key for the Extole_Deployer Connected App or External Client App
// Run via: sf apex run --file scripts/apex/get_consumer_key.apex

// Try legacy ConnectedApplication first
List<ConnectedApplication> apps = [
    SELECT ConsumerKey
    FROM ConnectedApplication
    WHERE Name = 'Extole Deployer'
    LIMIT 1
];
if (!apps.isEmpty()) {
    System.debug('CONSUMER_KEY: ' + apps[0].ConsumerKey);
    return;
}

// Try ExternalClientApplication (Spring '24+ External Client Apps)
try {
    List<SObject> extApps = Database.query(
        'SELECT ConsumerKey FROM ExternalClientApplication WHERE Name = \'Extole Deployer\' LIMIT 1'
    );
    if (!extApps.isEmpty()) {
        System.debug('CONSUMER_KEY: ' + (String) extApps[0].get('ConsumerKey'));
        return;
    }
} catch (Exception e) {
    System.debug('ExternalClientApplication query failed: ' + e.getMessage());
}

System.debug('CONSUMER_KEY: NOT_FOUND');
