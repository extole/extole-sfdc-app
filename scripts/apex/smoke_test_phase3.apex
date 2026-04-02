List<Extole_Event_Config__mdt> configs = [SELECT DeveloperName, Event_Name__c, Status__c FROM Extole_Event_Config__mdt];
System.debug('Configs: ' + configs.size());
List<Extole_Event_Log__c> logs = [SELECT Id FROM Extole_Event_Log__c LIMIT 1];
System.debug('Event logs queryable: ' + true);
