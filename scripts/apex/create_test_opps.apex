// Creates test Accounts, Contacts, and Opportunities for Extole event testing
// Opps are in Stage "6 - ..." (pre-close) so they can be moved to 7 - Closed/Won to fire the trigger

// 1. Account
Account acct = new Account(Name = 'Extole Test Account');
insert acct;

// 2. Contacts with test emails
List<Contact> contacts = new List<Contact>{
    new Contact(FirstName = 'Test', LastName = 'Alpha',   Email = 'alpha@extoletestemaildomain.com',   AccountId = acct.Id),
    new Contact(FirstName = 'Test', LastName = 'Bravo',   Email = 'bravo@extoletestemaildomain.com',   AccountId = acct.Id),
    new Contact(FirstName = 'Test', LastName = 'Charlie', Email = 'charlie@extoletestemaildomain.com', AccountId = acct.Id)
};
insert contacts;

// 3. Opportunities in stage 6 (pre-close)
List<Opportunity> opps = new List<Opportunity>{
    new Opportunity(Name = 'Extole Test Opp Alpha',   AccountId = acct.Id, StageName = '6 - Commit',     CloseDate = Date.today().addDays(30), Amount = 10000),
    new Opportunity(Name = 'Extole Test Opp Bravo',   AccountId = acct.Id, StageName = '6 - Commit',     CloseDate = Date.today().addDays(30), Amount = 20000),
    new Opportunity(Name = 'Extole Test Opp Charlie', AccountId = acct.Id, StageName = '6 - Commit',     CloseDate = Date.today().addDays(30), Amount = 30000)
};
insert opps;

// 4. OpportunityContactRoles linking each opp to a contact
List<OpportunityContactRole> roles = new List<OpportunityContactRole>{
    new OpportunityContactRole(OpportunityId = opps[0].Id, ContactId = contacts[0].Id, IsPrimary = true, Role = 'Decision Maker'),
    new OpportunityContactRole(OpportunityId = opps[1].Id, ContactId = contacts[1].Id, IsPrimary = true, Role = 'Decision Maker'),
    new OpportunityContactRole(OpportunityId = opps[2].Id, ContactId = contacts[2].Id, IsPrimary = true, Role = 'Decision Maker')
};
insert roles;

System.debug('=== Test Data Created ===');
System.debug('Account Id: ' + acct.Id);
for (Integer i = 0; i < opps.size(); i++) {
    System.debug('Opp: ' + opps[i].Name + ' | Id: ' + opps[i].Id + ' | Contact Email: ' + contacts[i].Email);
}
System.debug('Move any opp to "7 - Closed/Won" to fire the Extole trigger');
