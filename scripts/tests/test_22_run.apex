// Test 22 — Bulk event dispatch (>100 records)
// Step 3 of 3: Insert 150 leads in one transaction to trigger bulk Flow invocation
// Run: sf apex run --file scripts/tests/test_22_run.apex --target-org <alias>
//
// Pass criteria:
//   - 2 Queueable jobs appear in Setup → Apex Jobs (100 records + 50 records)
//   - Both jobs complete with Status = Completed and NumberOfErrors = 0
//   - Query: SELECT Id, Status, NumberOfErrors FROM AsyncApexJob
//            WHERE JobType = 'Queueable' AND CreatedDate = TODAY ORDER BY CreatedDate DESC

List<Lead> leads = new List<Lead>();
for (Integer i = 0; i < 150; i++) {
    leads.add(new Lead(
        FirstName = 'BulkTest',
        LastName  = 'Lead' + String.valueOf(i).leftPad(3, '0'),
        Email     = 'bulktest+' + i + '@extole-fake-test.invalid',
        Company   = 'Extole Bulk Test'
    ));
}
insert leads;
System.debug('Inserted ' + leads.size() + ' leads — check Apex Jobs for 2 Queueable jobs');
