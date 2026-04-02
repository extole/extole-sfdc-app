// PROBE 3: Create a Lead to trigger the Flow deployed in probe_2
// Run AFTER probe_2. The Flow should fire and enqueue Extole_Handler_probe_lead_created,
// which POSTs to Extole.
//
// Run with: sf apex run --file scripts/apex/probe_3_fire_event.apex -o extole-sandbox
//
// After running: check Extole dashboard for an event named "sfdc_lead_created"
// Also check Setup > Apex Jobs for the queued/completed Extole_Handler_probe_lead_created job

Lead l = new Lead(
    FirstName  = 'ProbeTest',
    LastName   = 'DynHandler',
    Company    = 'Extole Probe Co',
    LeadSource = 'Web'
);
insert l;
System.debug('Probe 3 — Lead inserted: ' + l.Id + ' — check Apex Jobs and Extole dashboard');
