Extole_Event_Cfg__c cfg = [
    SELECT Config_Key__c, Last_HTTP_Status__c, Last_Response_Summary__c,
           Last_Attempted_At__c, Last_Succeeded_At__c, Last_Failed_At__c,
           Last_Record_Id__c
    FROM Extole_Event_Cfg__c
    WHERE Config_Key__c = 'opportunity_closedwon_3'
    LIMIT 1
];
System.debug('HTTP Status: ' + cfg.Last_HTTP_Status__c);
System.debug('Response: ' + cfg.Last_Response_Summary__c);
System.debug('Attempted At: ' + cfg.Last_Attempted_At__c);
System.debug('Succeeded At: ' + cfg.Last_Succeeded_At__c);
System.debug('Failed At: ' + cfg.Last_Failed_At__c);
System.debug('Last Record Id: ' + cfg.Last_Record_Id__c);
