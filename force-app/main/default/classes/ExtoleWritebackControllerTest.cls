@IsTest
private class ExtoleWritebackControllerTest {

    @IsTest
    static void testGetEndpointUrl() {
        Test.startTest();
        String url = ExtoleWritebackController.getEndpointUrl();
        Test.stopTest();
        System.assertNotEquals(null, url);
        System.assert(url.contains('/services/apexrest/extole/events'));
    }

    @IsTest
    static void testSaveAndGetConfigs() {
        Extole_Writeback_Cfg__c cfg = new Extole_Writeback_Cfg__c(
            Name          = 'Test Rule',
            Event_Name__c = 'reward_earned',
            Object_Type__c = 'Contact',
            Status__c     = 'ACTIVE'
        );
        Test.startTest();
        ExtoleWritebackController.saveWritebackConfig(cfg);
        List<Extole_Writeback_Cfg__c> result = ExtoleWritebackController.getWritebackConfigs();
        Test.stopTest();
        System.assertEquals(1, result.size());
        System.assertEquals('reward_earned', result[0].Event_Name__c);
    }

    @IsTest
    static void testSaveUpdate() {
        Extole_Writeback_Cfg__c cfg = new Extole_Writeback_Cfg__c(
            Name          = 'Upd Rule',
            Event_Name__c = 'share_link_clicked',
            Object_Type__c = 'Lead',
            Status__c     = 'ACTIVE'
        );
        insert cfg;
        cfg.Status__c = 'INACTIVE';
        Test.startTest();
        ExtoleWritebackController.saveWritebackConfig(cfg);
        Test.stopTest();
        Extole_Writeback_Cfg__c updated = [SELECT Status__c FROM Extole_Writeback_Cfg__c WHERE Id = :cfg.Id];
        System.assertEquals('INACTIVE', updated.Status__c);
    }

    @IsTest
    static void testSaveValidationMissingEvent() {
        Extole_Writeback_Cfg__c cfg = new Extole_Writeback_Cfg__c(
            Object_Type__c = 'Contact',
            Status__c      = 'ACTIVE'
        );
        Test.startTest();
        try {
            ExtoleWritebackController.saveWritebackConfig(cfg);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null);
        }
        Test.stopTest();
    }

    @IsTest
    static void testDeleteConfig() {
        Extole_Writeback_Cfg__c cfg = new Extole_Writeback_Cfg__c(
            Name          = 'Del Rule',
            Event_Name__c = 'friend_registered',
            Object_Type__c = 'Lead',
            Status__c     = 'ACTIVE'
        );
        insert cfg;
        Test.startTest();
        ExtoleWritebackController.deleteWritebackConfig(cfg.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Extole_Writeback_Cfg__c WHERE Id = :cfg.Id]);
    }

    @IsTest
    static void testGetAndClearLogs() {
        Extole_Writeback_Log__c log = new Extole_Writeback_Log__c(
            Event_Name__c  = 'reward_earned',
            Status__c      = 'SUCCESS',
            Received_At__c = System.now()
        );
        insert log;
        Test.startTest();
        List<Extole_Writeback_Log__c> logs = ExtoleWritebackController.getWritebackLogs();
        System.assertEquals(1, logs.size());
        Map<String, Integer> result = ExtoleWritebackController.clearWritebackLogs();
        Test.stopTest();
        System.assertEquals(1, result.get('deletedCount'));
        System.assertEquals(0, result.get('remainingCount'));
        System.assertEquals(0, [SELECT COUNT() FROM Extole_Writeback_Log__c]);
    }
}
