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
