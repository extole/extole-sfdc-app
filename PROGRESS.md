# Extole SFDC App — Build Progress

## Status: Complete (v1)

All three phases of the build have been completed and verified.

---

## Phase 1: Custom Objects & Infrastructure

**Deployed:**
- `Extole_Report_Snapshot__c` — stores report values per config per date range
- `Extole_Report_Config__c` — defines which reports to sync and how to display them
- `Extole_Sync_Log__c` — records each sync run with status and row count
- `Extole_Debug_Log__c` — verbose HTTP request/response logging (opt-in)
- `Extole_App_Settings__c` — Custom Hierarchy Setting for org-level configuration
- Named Credential `Extole_API` → `https://my.extole.com` with Bearer token (via External Credential, token never committed to git)
- External Credential `Extole_API` using `authenticationProtocol=Custom` with `AuthHeader` parameter

**Key fixes during Phase 1:**
- `Sync_Cadence__c` changed from Picklist to Text (Hierarchy Custom Settings don't support Picklist)
- `ExternalCredential` XML uses `externalCredentialParameters` (repeated elements), not separate `principals`/`parameters` blocks
- `NamedCredential` XML uses `namedCredentialParameters` and `namedCredentialType`
- Named Credential principal access granted via `Extole_API_Access` PermissionSet assigned to user

---

## Phase 2: Apex Backend + LWC Frontend (parallel)

**Teammate A — Apex:**
- `ExtoleSyncJob.cls` — Schedulable sync job with POST → poll → download → extract pipeline
- `ExtoleController.cls` — `@AuraEnabled` controller for all LWC data access
- `ExtoleSyncJobTest.cls` — 20 unit tests, all passing

**Teammate B — LWC:**
- `extoleApp` — App shell with tab router
- `extoleProgramOverview` — Program Overview tab with date range toggle
- `extoleTile` — Metric tile with SVG sparkline/bar chart rendering
- `extoleSettings` — Settings tab with 5 configuration sections
- `extoleLeadAttribution` — Lead Attribution tab
- `extoleOnboarding` — 3-step onboarding flow

**Supporting metadata:**
- 98 Custom Labels (all UI strings externalized)
- Extole logo SVG static resource

---

## Phase 3: Integration & Verification

**Deployed:**
- `Extole_App_Admin` PermissionSet — full CRUD on all 4 objects + ExternalCredentialPrincipalAccess + RunFlow
- `Extole_App_Viewer` PermissionSet — read-only access to Snapshot and Config objects
- `Display_Label__c` field added to `Extole_Report_Snapshot__c` (required by LWC tile rendering)

**Bugs found and fixed during integration:**
1. **`report_id` field name** — Extole API returns `report_id` in POST /v4/reports response, not `id`. Fixed in `ExtoleSyncJob.cls` (lines 155, 157, 430) and `ExtoleController.cls` (line 212).
2. **`PROCESSING` vs `PENDING` status** — Initial report status from API is `PENDING`, not `PROCESSING`. `ExtoleController.triggerSingleSync()` polling condition updated from `status == 'PROCESSING'` to `status != 'DONE' && status != 'FAILED'`.
3. **Custom field visibility in anonymous Apex** — Custom fields on `Extole_Report_Config__c` and `Extole_Report_Snapshot__c` are not visible via anonymous Apex or REST API describe (metadata cache issue). Workaround: use compiled controller methods (`ExtoleController.saveConfig()`, `getConfigs()`, `getSnapshots()`) or JSON deserialization.

**End-to-end test results:**
- Named Credential connectivity: ✅ HTTP 200 from `GET /v6/report-types`
- Report submission: ✅ POST /v4/reports returns HTTP 200 with `report_id`
- Report data extraction: ✅ `extractValue('acquisition_rate', 'FIRST_ROW')` → `"0.18"` from real ACQUISITION_RATE report
- Snapshot creation: ✅ `Extole_Report_Snapshot__c` record inserted and returned by `getSnapshots()`
- Unit tests: ✅ 20/20 passing

**Production note — SPARK report timing:**
ACQUISITION_RATE is a SPARK executor type that takes ~7-8 minutes to complete. The sync job's 40-retry polling limit covers ~40-60 seconds, which is insufficient. In production deployments using SPARK report types, operators should either:
- Use CONFIGURED or SQL executor types (complete in seconds)
- Increase `maxRetriesFor('SPARK')` to match expected report duration
- Or accept that SPARK syncs will be marked FAILED and retry on next scheduled run

---

## Deployed Metadata Summary

| Type | Name |
|------|------|
| CustomObject | Extole_Report_Snapshot__c |
| CustomObject | Extole_Report_Config__c |
| CustomObject | Extole_Sync_Log__c |
| CustomObject | Extole_Debug_Log__c |
| CustomObject | Extole_App_Settings__c |
| ExternalCredential | Extole_API |
| NamedCredential | Extole_API |
| ApexClass | ExtoleSyncJob |
| ApexClass | ExtoleSyncJobTest |
| ApexClass | ExtoleController |
| LightningComponentBundle | extoleApp |
| LightningComponentBundle | extoleProgramOverview |
| LightningComponentBundle | extoleTile |
| LightningComponentBundle | extoleSettings |
| LightningComponentBundle | extoleLeadAttribution |
| LightningComponentBundle | extoleOnboarding |
| CustomLabels | 98 labels |
| PermissionSet | Extole_App_Admin |
| PermissionSet | Extole_App_Viewer |
| PermissionSet | Extole_API_Access |
| StaticResource | extole_logo |
| LightningApplication | Extole_App |
| CustomTab | 3 tabs |

---

---

## v2 Pre-Build Spike: Type.forName() Coverage (completed 2026-03-26)

**Result: PASSED — generic test harness approach is viable.**

`Extole_Handler_spike_test` (Queueable pattern) achieved **100% coverage** when invoked from `ExtoleEventHandlerTest` using both `Type.forName()` dynamic resolution and direct static invocation. Both test methods passed.

**Decision:** Use the generic test harness approach — a single `ExtoleEventHandlerTest` class using `Type.forName()` to cover all generated handlers. No per-handler test class generation required.

Spike classes deployed to `extole-sandbox`:
- `Extole_Handler_spike_test` — sample generated handler (Queueable pattern)
- `ExtoleEventHandlerTest` — generic test harness (ships with the package)

---

## v2 Phase 1: Data Model Extension (completed 2026-03-26)

**Status: COMPLETE — both objects deployed and queryable in extole-sandbox.**

### Deployed

**`Extole_Event_Config__mdt`** — Custom Metadata Type, 24 fields:
- Core: `Config_Key__c`, `Config_Version__c`, `Event_Name__c`
- Trigger: `Trigger_Object__c`, `Trigger_Type__c` (CREATED/UPDATED/FIELD_EQUALS/FIELD_CHANGES), `Trigger_Field__c`, `Trigger_Value__c`, `Trigger_From_Value__c`, `Trigger_To_Value__c`
- Generated artifacts: `Apex_Class_Name__c`, `Flow_Name__c`
- State: `Status__c` (ACTIVE/INACTIVE/DRAFT/DEPLOY_FAILED), `Active__c`, `Deploy_Error__c`, `Deploy_Error_Raw__c`
- Audit: `Last_Deployed__c`, `Deployed_By_User_Id__c`, `Last_Tested_Record_Id__c`
- Runtime telemetry: `Last_Attempted_At__c`, `Last_Succeeded_At__c`, `Last_Failed_At__c`, `Last_Record_Id__c`, `Last_HTTP_Status__c`, `Last_Response_Summary__c`
- Storage: `Field_Mappings_JSON__c` (LongTextArea, serialized field mapping array)

**`Extole_Event_Log__c`** — Custom Object (always-on logging), 7 fields:
- `Config_Key__c`, `Event_Type__c` (10-value picklist per spec), `User_Id__c`, `Timestamp__c`, `Result__c` (SUCCESS/FAILED/CANCELLED/FOUND/NOT_FOUND/UNKNOWN), `Detail__c`, `Sync_Batch_Id__c`
- AutoNumber name field: EVT-{0000}

**Three preset `Extole_Event_Config__mdt` records** (all in DRAFT state):
- `Lead_Created` — Lead, CREATED, maps Id/FirstName/LastName/Email/Company to `lead_created`
- `Lead_Converted` — Lead, FIELD_EQUALS IsConverted=true, same field mappings to `lead_converted`
- `Opportunity_Closed_Won` — Opportunity, FIELD_EQUALS StageName=Closed Won, maps Id/Name/Amount to `opportunity_closedwon`

### Verification
- `SELECT DeveloperName, Event_Name__c, Trigger_Type__c, Status__c FROM Extole_Event_Config__mdt` → 3 records returned
- `SELECT Id FROM Extole_Event_Log__c LIMIT 5` → 0 records, no error (object queryable)

### Next: Phase 2
Ready to spawn Teammate A (Apex/backend) and Teammate B (LWC/frontend) in parallel.

---

## v2 Phase 2: LWC Frontend (completed 2026-03-26)

**Status: COMPLETE — all deliverables written, ready for deploy.**

### Deliverables

**New LWC components:**

| Component | Role |
|---|---|
| `extoleEventConfigurator` | Main tab — list view of all event configs, row actions (Edit/Delete), empty state, delete dependency check modal |
| `extoleEventModal` | Three-step add/edit modal: Choose Trigger → Map Fields → Review & Deploy |

**`extoleEventConfigurator` feature summary:**
- List view using `lightning-datatable` with columns: Event Name, Trigger (human-readable), Status badge (color-coded SLDS), Last Deployed, Last Fire (HTTP status + summary)
- Row actions: Edit (opens modal pre-filled), Delete (opens dependency check modal)
- `lightning-illustration` empty state with "Configure Your First Event" CTA
- Delete modal: shows "Checking Extole campaign usage…" spinner immediately, calls `ExtoleEventController.checkEventUsage()`, 10s timeout → UNKNOWN fallback
  - NOT_FOUND: normal Delete / Cancel
  - FOUND: warning + campaign name, Deactivate (primary) + Delete anyway (de-emphasized)
  - UNKNOWN: Deactivate (primary) + Delete anyway
- "Clear Event Log" button calls `ExtoleEventController.clearEventLog()`
- Imperative Apex calls, `ShowToastEvent` for success/error, `@track` throughout

**`extoleEventModal` feature summary:**
- Step 1 — Choose Trigger: 4 clickable preset cards (Lead Created, Lead Converted, Opportunity Won, Custom); searchable object combobox (calls `getAvailableObjects()`, common objects first); trigger condition combobox (CREATED/UPDATED/FIELD_EQUALS/FIELD_CHANGES); conditional field/value inputs for FIELD_EQUALS and FIELD_CHANGES
- Step 2 — Map Fields: event name input with tooltip; required section (email + partner_user_id) with field picker or static value toggle, auto-defaults to Email/Id fields, no-email-field warning banner; optional params add-row table with paramName input + field picker/static toggle + Remove; app_type auto-injection note; null field exclusion note; calls `getFieldsForObject()`
- Step 3 — Review & Deploy: summary card (object, trigger, event name), field mappings table with required badges, generated artifact names (Apex class + Flow); test with sample record (record ID input → `previewPayload()` → formatted JSON payload); payload diff on edit (added/removed/changed rows color-coded); Deploy button → `deployEventConfig()` → polling via `pollDeployStatus()` → success/failure inline; back/next navigation
- Full label coverage — no hardcoded UI strings

**Metadata updated:**
- `CustomLabels.labels-meta.xml` — 80+ new v2 labels added (tab, list view, step titles, preset cards, field labels, tooltips, diff, delete modal, error messages, status values)
- `tabs/Extole_Event_Configurator.tab-meta.xml` — new Custom Tab pointing to `extoleEventConfigurator` LWC
- `applications/Extole_App.app-meta.xml` — `Extole_Event_Configurator` tab added between Lead Attribution and Settings
- `extoleApp.html` — Event Configurator tab added to tab router (between Lead Attribution and Settings)
- `extoleApp.js` — `Extole_Tab_EventConfigurator` label imported and exposed
- `permissionsets/Extole_App_Admin.permissionset-meta.xml` — `Extole_Event_Log__c` object permissions added; `Extole_Event_Configurator` tab set to Visible

### Pending (Teammate A — Apex)
The following Apex methods are called by these components and must be implemented in `ExtoleEventController`:
- `getEventConfigs()` → returns `List<Extole_Event_Config__mdt>` with all fields
- `deleteEventConfig(String configKey)` → deactivates Flow, deletes config record
- `deactivateEventConfig(String configKey)` → sets Status__c = INACTIVE, deactivates Flow
- `checkEventUsage(String eventName)` → calls Extole API, returns JSON `{status, campaignName, campaignId}`
- `clearEventLog()` → deletes all `Extole_Event_Log__c` records
- `getAvailableObjects()` → returns JSON `[{label, value, isCommon}]`
- `getFieldsForObject(String objectApiName)` → returns JSON `[{label, apiName, type}]` (one-hop related fields included)
- `previewPayload(String configJson, String recordId)` → returns JSON payload that would be sent
- `deployEventConfig(String configJson)` → initiates async deploy, returns jobId
- `pollDeployStatus(String jobId)` → returns JSON `{status, errorMessage}` where status is PENDING/SUCCEEDED/FAILED

---

## v2 Phase 2: Apex Backend (completed 2026-03-26)

**Status: COMPLETE — all four service classes written, test class expanded to 90%+ target coverage.**

### Deliverables

**New Apex classes:**

| Class | Role |
|---|---|
| `ExtoleToolingService` | Generates and deploys Apex handler classes via Salesforce Tooling API (session auth). Handles create, PATCH, and delete of ApexClass records. Includes handler body code generation (Queueable + AllowsCallouts), one-hop relationship field traversal, null-field omission, and runtime telemetry callbacks. |
| `ExtoleMetadataService` | Deploys, deactivates, and deletes Record-Triggered Flows via Metadata API. Also provides `upsertCmdtRecord()` for writing telemetry and state back to `Extole_Event_Config__mdt`. Generates compliant Flow XML for all four trigger types. |
| `ExtoleSafetyCheckService` | Calls Extole campaigns API with 10-second timeout. Scans three known response shapes for event name references. Returns FOUND/NOT_FOUND/UNKNOWN. Only active/published campaigns count as FOUND. Draft/paused/archived ignored. |
| `ExtoleEventController` | All `@AuraEnabled` methods for the LWC tab. Includes deploy orchestration (version increment → Tooling deploy → deactivate old flow → deploy new flow → update CMDT), orphan cleanup, previewPayload, schema inspection. |

**Updated:**

| Class | Changes |
|---|---|
| `ExtoleEventHandlerTest` | Expanded from 2 spike tests to 40+ test methods covering all four new classes. Mock infrastructure: ConfigurableMock (pattern-based per-endpoint responses), SuccessMock, TimeoutMock. Covers: Tooling API success/403/PATCH, handler body generation (direct fields, one-hop, static values), flow XML generation (all four trigger types), safety check (FOUND/NOT_FOUND/UNKNOWN, all three response shapes, case-insensitive, timeout, bad JSON), previewPayload with real Lead record, null field omission, controller orchestration methods. |

### Design decisions made during implementation

1. **Handler body uses `Database.query()` (dynamic SOQL)** — avoids compile-time schema dependency in the generated string. The field list is already validated at config-save time by the LWC.

2. **Telemetry update via `ExtoleMetadataService.upsertCmdtRecord()`** — generated handlers call `ExtoleToolingService.updateConfigTelemetry()` as a public static, which delegates to the Metadata API. Failures are swallowed (log only) so a telemetry write failure never crashes event delivery.

3. **Flow deployment uses REST Metadata API** (`/services/data/v59.0/tooling/` query + REST PATCH/POST) for single-file components rather than SOAP deploy-with-zip. Simpler, no zip encoding required. SOAP used only for `upsertMetadata` (CMDT) and `deleteMetadata`.

4. **`getAvailableObjects()` uses `SortableObject implements Comparable`** — Apex's `List.sort()` does not support Comparator on `List<Map<String,Object>>`. Inner class wrapper provides alphabetical sort on label with priority objects pinned first.

5. **`saveEventConfig` accepts a JSON String** rather than a typed CMDT sObject — LWC cannot serialize CMDT records with all custom fields through standard `@AuraEnabled` method parameters. JSON string gives full flexibility.

6. **`deployEventConfig` is synchronous** — calls Tooling API and Metadata API inline. Timeout risk is acceptable for admin-initiated deploys (typically < 5 seconds). If the org's Tooling API is slow, the LWC's deploy button shows a spinner.

### Notes for deploy

- All new classes: `--test-level NoTestRun` for deploy to `extole-sandbox`
- Requires `Author Apex` and `Customize Application` on the running user
- `ExtoleEventController.deactivateEventConfig()` and `clearEventLog()` referenced by LWC (Teammate B) are not yet implemented — add in the next iteration if Teammate B's components call them before the next round

---

---

## v2 Phase 3: Integration, Deployment & Verification (completed 2026-03-26)

**Status: COMPLETE**

### Integration Gaps Found and Resolved

Three `@AuraEnabled` methods were called by LWC components but missing from `ExtoleEventController`:

| Method | Component | Resolution |
|--------|-----------|------------|
| `deactivateEventConfig(String configKey)` | `extoleEventConfigurator.js` | Added — sets Status__c=INACTIVE, deactivates Flow via MetadataService, writes log |
| `clearEventLog()` | `extoleEventConfigurator.js` | Added — bulk-deletes all Extole_Event_Log__c records |
| `pollDeployStatus(String jobId)` | `extoleEventModal.js` | Added — queries CMDT Status__c as proxy for synchronous deploy outcome |

**Additional signature mismatches fixed:**

- `deployEventConfig` — LWC sends `{ configJson }` (full config object JSON), not just a configKey. Method refactored to accept `String configJson`, save/upsert the CMDT record, then invoke internal deploy sequence. Returns `String jobId` (= configKey) for polling.
- `previewPayload` — LWC sends `{ configJson, recordId }` (config object + record Id). Method refactored from 4-parameter signature to `(String configJson, Id recordId)`, parsing `triggerObject`, `fieldMappingsJson`, and `eventName` from the config JSON.

**Compile errors fixed in Apex (reserved word violations):**

- `ExtoleEventHandlerTest.cls`: Method named `on` is a reserved word in Apex — renamed to `addPattern` with all 11 call sites updated.
- `ExtoleEventHandlerTest.cls`: `System.assertNull()` is not a valid Apex method — replaced with `System.assertEquals(null, ...)`.
- `ExtoleSafetyCheckService.cls`: Variable `inner` is reserved — renamed to `campaignsRaw`.
- `ExtoleSafetyCheckService.cls`: Variable `trigger` is reserved — renamed to `trig`.

**LWC HTML fix:**

- `extoleEventModal.html` line 379: `lwc:if={row.type === 'added'}` uses an inline expression which is invalid LWC template syntax. Fixed by adding boolean properties `isAdded`, `isRemoved`, `isChanged` to each diff row object in the JS, then using `lwc:if={row.isAdded}` in the template.

**Custom Label audit:** All 80+ v2 labels used by LWC components confirmed present in `CustomLabels.labels-meta.xml`. No missing labels.

### Deploy Order and Results

| Step | Components | Result |
|------|-----------|--------|
| 1 | Apex: `ExtoleToolingService`, `ExtoleMetadataService`, `ExtoleSafetyCheckService`, `ExtoleEventController`, `ExtoleEventHandlerTest` | Succeeded (Deploy ID: 0AfQL00000lDzSS0A0) |
| 2 | Metadata: `CustomLabels.labels-meta.xml` | Succeeded (80+ new labels deployed) |
| 3 | LWC: `extoleEventConfigurator`, `extoleEventModal`, `extoleApp`; Tab: `Extole_Event_Configurator` | Succeeded (Deploy ID: 0AfQL00000lDyEc0AK) |
| 4 | App: `Extole_App`; Permission Set: `Extole_App_Admin` | Succeeded (Deploy ID: 0AfQL00000lE4VJ0A0) |

**First deploy attempt failures (both fixed before retry):**
- Apex compile errors: reserved words `on`, `inner`, `trigger`; invalid `System.assertNull`
- LWC HTML error: inline expression in `lwc:if` attribute
- Permission set: referenced `Extole_Event_Configurator` tab before tab was deployed — resolved by deploying tab in step 3 before permission set in step 4

### Test Results

**Test run:** `ExtoleEventHandlerTest` — 80 tests, 100% pass rate

| Class | Coverage | Status |
|-------|----------|--------|
| `Extole_Handler_spike_test` | 100% | ✅ |
| `ExtoleMetadataService` | 97% | ✅ |
| `ExtoleSafetyCheckService` | 93% | ✅ |
| `ExtoleToolingService` | 85% | ✅ |
| `ExtoleEventController` | 81% | ✅ |

All classes exceed the 75% coverage threshold.

**New tests added (18 test methods):** `testDeployFlow_success`, `testDeployFlow_fieldEquals`, `testDeployFlow_existingClass_patch`, `testDeployFlow_error_throws`, `testDeactivateFlow_success`, `testDeleteFlow_success`, `testDeleteFlow_soapError_throws`, `testDeleteFlow_soapSuccessFalse_throws`, `testPreviewPayload_recordNotFound`, `testPreviewPayload_oneHopRelationship`, `testDeactivateEventConfig_configNotFound`, `testDeactivateEventConfig_success`, `testClearEventLog_success`, `testPollDeployStatus_blankJobId`, `testPollDeployStatus_configNotFound`, `testPollDeployStatus_active`, `testDeleteEventConfig_configNotFound`, `testDeleteEventConfig_success`

### Smoke Test

Anonymous Apex executed against `extole-sandbox`:
- `SELECT DeveloperName, Event_Name__c, Status__c FROM Extole_Event_Config__mdt` → **3 records** (Lead_Created, Lead_Converted, Opportunity_Closed_Won)
- `SELECT Id FROM Extole_Event_Log__c LIMIT 1` → **queryable**, no error

### Items Deferred to Future Iteration

- `leadRoundRobin` class coverage is 24% — this is a pre-existing v1 class not part of Phase 3; no action taken per rules.
- `ExtoleToolingService` lines 85-86, 115, 330-331: These are error-path branches in handler body generation and Tooling API delete that require complex mock setup. Coverage is 85% which exceeds the 75% threshold.
- `ExtoleSafetyCheckService` lines 71, 73: These are the `Exception` catch branches (non-CalloutException). Coverage is 93% which exceeds threshold.

---

## Test Account Config

A test `Extole_Report_Config__c` record is deployed in the org:
- **Report Type:** ACQUISITION_RATE
- **Executor Type:** SPARK
- **Display Label:** Acquisition Rate
- **Value Column:** acquisition_rate
- **Aggregation:** FIRST_ROW
- **Chart Type:** Sparkline

A test `Extole_Report_Snapshot__c` record has been inserted with real data:
- **Value:** 0.18 (acquisition rate for Rolling 30 days)
- **Report ID:** tcfhu459ag0xzudsd0kp
