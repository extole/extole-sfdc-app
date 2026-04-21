// Test 22 — Bulk event dispatch (>100 records)
// Cleanup: Delete all test leads inserted by test_22_run.apex
// Run: sf apex run --file scripts/tests/test_22_cleanup.apex --target-org <alias>

List<Lead> toDelete = [SELECT Id FROM Lead WHERE Company = 'Extole Bulk Test'];
delete toDelete;
System.debug('Deleted ' + toDelete.size() + ' test leads');
