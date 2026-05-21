global without sharing class ExtoleWritebackController {

    @AuraEnabled(cacheable=false)
    public static String getEndpointUrl() {
        return System.URL.getOrgDomainURL().toExternalForm() + '/services/apexrest/extole/events';
    }

    @AuraEnabled(cacheable=false)
    public static List<Extole_Writeback_Cfg__c> getWritebackConfigs() {
        return [
            SELECT Id, Name, Event_Name__c, Object_Type__c, Status__c,
                   Field_Mappings__c, Description__c
            FROM Extole_Writeback_Cfg__c
            ORDER BY Event_Name__c ASC, Object_Type__c ASC
        ];
    }

    @AuraEnabled
    public static void saveWritebackConfig(Extole_Writeback_Cfg__c config) {
        if (String.isBlank(config.Event_Name__c)) {
            throw new AuraHandledException('Event name is required.');
        }
        if (String.isBlank(config.Object_Type__c)) {
            throw new AuraHandledException('Object type is required.');
        }
        if (String.isBlank(config.Status__c)) {
            config.Status__c = 'ACTIVE';
        }
        if (config.Id == null) {
            insert config;
        } else {
            update config;
        }
    }

    @AuraEnabled
    public static void deleteWritebackConfig(Id configId) {
        delete [SELECT Id FROM Extole_Writeback_Cfg__c WHERE Id = :configId LIMIT 1];
    }

    @AuraEnabled(cacheable=false)
    public static List<Extole_Writeback_Log__c> getWritebackLogs() {
        return [
            SELECT Id, Name, Event_Name__c, Event_Id__c, Email__c, Salesforce_Id__c,
                   Object_Type__c, Record_Id__c, Status__c, Error__c, Received_At__c
            FROM Extole_Writeback_Log__c
            ORDER BY Received_At__c DESC
            LIMIT 200
        ];
    }

    @AuraEnabled
    public static Map<String, Integer> clearWritebackLogs() {
        List<Extole_Writeback_Log__c> toDelete = [
            SELECT Id FROM Extole_Writeback_Log__c LIMIT 2000
        ];
        Integer deleted = toDelete.size();
        if (!toDelete.isEmpty()) delete toDelete;
        Integer remaining = [SELECT COUNT() FROM Extole_Writeback_Log__c];
        return new Map<String, Integer>{ 'deletedCount' => deleted, 'remainingCount' => remaining };
    }
}
