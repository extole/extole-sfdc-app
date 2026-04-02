// Check async apex jobs from recent 5 minutes
String jobId = '0AfQL00000lMNUL0A4';
System.debug('CHECKING_JOB: ' + jobId);

// Use SOQL in a method call context to avoid parse ambiguity
Integer jobCount = [SELECT COUNT() FROM AsyncApexJob WHERE CreatedDate = LAST_N_MINUTES:5];
System.debug('ASYNC_JOBS_LAST_5MIN: ' + jobCount);

// Check if the CustomMetadata record was deployed (indirect check)
Integer mdtCount = [SELECT COUNT() FROM Extole_Event_Config__mdt WHERE DeveloperName = 'Spike_Test'];
System.debug('SPIKE_TEST_MDT_EXISTS: ' + mdtCount);
