# Extole SFDC App – v2 Spec: Event Configurator

## Overview

The Event Configurator extends the Extole SFDC App with a no-code UI for configuring SFDC→Extole event flows. Instead of writing Apex callout classes and Flows manually (or relying on Zapier), SFDC admins configure event mappings through a guided UI inside the app. The configurator dynamically inspects the client's SFDC org, generates the necessary Apex and Flow components, and deploys them — no code required, no third-party dependency, no additional cost.

**The business case:** Zapier is the current path of least resistance for SFDC→Extole event configuration, but clients balk at the direct per-task cost and the additional account/approval overhead. The configurator eliminates that friction entirely — it's part of the Extole package the client already installed.

**The positioning principle:** Extole is the event destination. The configurator is the pipe. No developer required, no Zapier, no SI.

---

## What the Configurator Does

The admin picks:
- Which SFDC object triggers the event
- Which condition fires the trigger (record created, record updated, field equals value)
- What to call the event in Extole (`event_name`)
- Which SFDC fields map to which Extole event parameters

The package handles:
- Dynamically inspecting the org for available objects and fields
- Generating the Apex callout class
- Generating the Flow that calls it
- Deploying both to the org using the admin's session credentials
- No additional Named Credentials or Connected Apps required beyond the existing Extole API credential

---

## Why Dynamic Object Inspection Matters

The configurator does not assume a fixed set of SFDC objects. It queries the org's metadata at runtime to enumerate all available objects — standard and custom. This makes it vertical-agnostic:

- **Telecom** — `Service_Scheduled__c` fires when a technician appointment is booked
- **Financial services** — `Account_Opening__c` fires when a new account is created
- **E-commerce** — `Order__c` fires when an order is fulfilled
- **Any vertical** — whatever conversion event matters to that client's program

This is why the three events documented on dev.extole.com (Lead Created, Lead Converted, Opportunity Closed/Won) are presets, not the ceiling.

---

## App Structure Changes

The Event Configurator adds a fourth tab to the existing app:

| Tab | Default State | Config Flag |
|---|---|---|
| Program Overview | Always visible | — |
| Lead Attribution | Hidden until enabled | `Show_Lead_Attribution__c` |
| **Event Configurator** | Always visible (admin only) | — |
| Settings | Always visible (admin only) | — |

The Event Configurator tab requires `Extole_App_Admin` permission set.

---

## Prerequisites

Before the Event Configurator can deploy generated components, the installing admin must have:
- **Author Apex** permission — required for Tooling API access to ApexClassMember
- **Customize Application** permission — required for Flow deployment via Metadata API

Add both to the CSM pre-installation checklist for v2.

---

## Tab: Event Configurator

### Overview State

Lists all configured event flows for this org. Each row shows:
- Event name (as it will appear in Extole)
- Triggering object and condition
- Status: Active / Inactive / Draft / Deploy Failed
- Last deployed timestamp
- Edit and Delete actions

"+ Add Event" button opens the configuration modal.

---

### Configuration Modal: Three Steps

#### Step 1: Choose Trigger

**Object picker:**
- Calls Salesforce Metadata API to enumerate all objects available in the org — standard and custom
- Searchable dropdown with object label and API name shown
- Common objects surfaced at top (Lead, Opportunity, Contact, Account)
- Custom objects clearly labeled

**Trigger condition:**
- Record created
- Record updated
- Field equals value (reveals field picker and value input)
- Field changes from / to (reveals field picker and two value inputs)

**Preset templates** (shown as suggested starting points, not required):

| Template | Object | Condition | Extole Event Name |
|---|---|---|---|
| Lead created | Lead | Record created | `lead_created` |
| Lead converted | Lead | IsConverted equals True | `lead_converted` |
| Opportunity won | Opportunity | StageName equals Closed Won | `opportunity_closedwon` |
| Custom | Any | Any | (admin defined) |

Admin can start from a preset and customize, or build from scratch.

#### Step 2: Map Fields

**Extole event name:**
- Text field for the `event_name` value sent to Extole
- Pre-filled from preset if selected
- Suggestions shown for common Extole event names

**Required parameters — validation rules:**
- `email` — always required. Field picker defaults to standard Email field on the selected object. Save is blocked if unmapped. If the selected object has no email-like field, admin must map a related object field or enter a static value — the UI surfaces a warning when no obvious email field is detected.
- `partner_user_id` — required but overridable. Defaults to the record Id field. Admin can remap to any field or static value. Cannot be left blank.
- Save is blocked if either required parameter is unmapped.

**Optional parameters:**
- Admin can add as many additional field mappings as needed
- Left side: Extole parameter name (free text)
- Right side: SFDC field picker — dynamically populated from fields on the selected object, plus fields from directly related objects (one relationship hop only in v1 — e.g. Account fields on a Lead, but not Account's parent fields). Only admin-visible, queryable relationship fields are included.
- Static value option — admin can hardcode a value rather than mapping a field

**`app_type` parameter:**
- Always included automatically, always set to `salesforce_crm`
- Not shown as a configurable field — injected by the generated Apex

**Null value handling:**
- If a mapped SFDC field is null at runtime, the parameter is omitted from the JSON payload rather than sent as null
- Admin is shown a note: "If a mapped field has no value on a record, that parameter will be excluded from the event payload"

**Related object field traversal:**
- One relationship hop supported in v1 (e.g. Lead.Account.Name)
- Only standard and custom lookup/master-detail relationships included
- Polymorphic relationships (e.g. Task.WhoId) excluded in v1
- Field picker labels relationship fields clearly: "Account: Name" not just "Name"

#### Step 3: Review & Deploy

Summary of the configuration:
- Triggering object and condition
- Event name
- Field mappings table
- Generated Apex class name and Flow name (shown for reference — see Naming below)

**No Event Streams live view.** Embedding a live Extole Event Streams panel in the configurator is intentionally not built. The polling mechanism, connection state management, and streaming API edge cases represent high maintenance overhead relative to the value. The "last fire" fields on each config record answer the primary operational question — "did my event fire?" — without a streaming subsystem. The link to Extole Event Streams on the deploy success screen handles deeper inspection. These two together cover the post-deploy verification need cleanly. A test fire against a real record could trigger reward logic, send emails to real people, or create unintended referral attribution in the Extole program. The payload preview in Step 3 covers the legitimate pre-deploy verification need — the admin sees exactly what would be sent without actually sending it.

**Test before deploy:**
- "Test with sample record" — admin picks a specific record from the org, the configurator previews the exact JSON payload that would be sent to Extole, without actually sending it
- Confirms field mappings are correct before deployment

**Deploy button:**
- Generates Apex class using Tooling API (session-based auth)
- Generates Record-Triggered Flow via Metadata API
- Deploys both to the org
- Stores configuration in `Extole_Event_Config__mdt`
- Activates the Flow automatically on successful deploy

**On deploy failure:**
- Status set to Deploy Failed
- Configurator parses Tooling API and Metadata API error responses and shows a human-readable message inline. Examples:
  - "The field `AdvocateCode__c` does not exist on Lead."
  - "The generated SOQL query is invalid because `Account.Owner.Email` is not queryable in this context."
  - "The running admin does not have Author Apex permission."
- Translation covers the top 10-15 common errors. Falls back to raw error text for unmapped errors.
- Raw platform error retained in `Deploy_Error_Raw` for support/debugging. UI defaults to translated message in `Deploy_Error`.
- Configuration preserved in Draft state — admin can edit and retry.

**Payload diff on edit:**
When editing an existing event configuration, the Review & Deploy step shows a before/after payload diff comparing the currently deployed configuration to the pending changes. Shown only on edit — not on first create.

The diff highlights:
- Added parameters (shown in success color)
- Removed parameters (shown in danger color)
- Changed field mappings or static values
- Event name changes

Diff is based on rendered JSON payload shape — not raw metadata — so the admin sees effective downstream impact before redeploying. If the trigger condition changed, that is shown separately above the payload diff.

Admin can toggle between Field mapping diff and Rendered payload diff views. Diff is not a generalized JSON diff engine — just a structured comparison of outgoing payload keys and values.

---

## Generated Component Naming

Generated artifacts use a stable config key derived from the `Extole_Event_Config__mdt` record's developer name, not the raw event name. This prevents collisions when two configs share the same event name or when an admin changes a label.

**Pattern:**
- Apex class: `Extole_Handler_[ConfigKey]` (e.g. `Extole_Handler_lead_created_a1b2`)
- Flow: `Extole_Flow_[ConfigKey]` (e.g. `Extole_Flow_lead_created_a1b2`)

`ConfigKey` is derived from the metadata record's developer name, which is unique within the org. Shown to the admin in the Step 3 review screen for reference.

**Edit behavior — explicit decision:** editing a config always deploys a new handler class with an incremented version suffix (`_v2`, `_v3`, etc.) rather than overwriting the existing class. The Flow is updated to point to the new class. The old class is retained as an orphan until manually cleaned up. This avoids the risk of overwriting a class that may still be referenced elsewhere.

---

## Generated Components

### Generated Apex Class

Uses **Queueable Apex with `Database.AllowsCallouts`** — not `@future(callout=true)`. Reason: `@future` is capped at 50 calls per transaction; a bulk import of 200 leads would silently drop events beyond that limit. Queueable jobs are enqueued per record and execute asynchronously with no per-transaction ceiling.

```apex
public with sharing class Extole_Handler_[ConfigKey] implements Queueable, Database.AllowsCallouts {

    private List<String> recordIds;

    public Extole_Handler_[ConfigKey](List<String> recordIds) {
        this.recordIds = recordIds;
    }

    @InvocableMethod
    public static void invoke(List<String> recordIds) {
        System.enqueueJob(new Extole_Handler_[ConfigKey](recordIds));
    }

    public void execute(QueueableContext ctx) {
        List<[Object]> records = [SELECT [configured fields]
                                  FROM [Object]
                                  WHERE Id IN :recordIds];
        for ([Object] r : records) {
            String body = JSON.serialize(new Map<String, Object>{
                'event_name' => '[configured event_name]',
                'data' => new Map<String, Object>{
                    // configured field mappings — null fields omitted
                    'app_type' => 'salesforce_crm'
                }
            });
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Extole_API/v5/events');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
            HttpResponse res = new Http().send(req);
            // update Last_* fields on Extole_Event_Config__mdt record
        }
    }
}
```

**CMDT management:** Event configuration records are stored in `Extole_Event_Config__mdt` and created, updated, and deleted by the configurator through Salesforce metadata APIs. The app does not rely on manual Setup edits to maintain runtime state. Updates are package-safe in subscriber orgs — existing config records are preserved across package upgrades.

### Generated Flow

Record-Triggered Flow per event configuration:
- Object: configured triggering object
- Trigger: configured condition
- Action: calls the generated Apex class via `@InvocableMethod`
- Auto-activated on successful deploy

---

## Package Unit Tests

All non-generated Apex classes in the package require their own test classes with mock HTTP callouts. These are distinct from the generated handler test classes. Minimum coverage requirement is 75% per class — target 90%+.

Required test classes:

| Class | What to test |
|---|---|
| Tooling API service class | Apex class creation, update, delete — mock Tooling API responses including success, 403, timeout |
| Metadata API service class | Flow deployment, deactivation — mock Metadata API responses |
| Safety check service | FOUND, NOT_FOUND, UNKNOWN outcomes — mock campaign API responses and timeout |
| `@AuraEnabled` controllers | All LWC data access methods — mock object/field enumeration and config reads |
| Sync job (v1) | Report execution, polling, download, snapshot upsert — mock Extole API responses |
| Post-install script | Email sends correctly — mock email service |
| Sync failure notification | Triggers after N consecutive failures, resets on manual sync success |

All test classes use `Test.setMock(HttpCalloutMock.class, ...)` — no real API calls in tests. Test classes must pass in both sandbox and production org contexts.

**Primary approach: generate a test class per handler at deploy time.**

Each deployment generates two classes — the handler and a corresponding minimal test class (`Extole_Test_[ConfigKey]`) — in the same deployment transaction. The test class follows a fixed template:

1. Creates a mock record for the target object
2. Sets `HttpCalloutMock` to simulate the Extole API response
3. Invokes the static `@InvocableMethod` directly
4. Asserts a 200 response

This is the reliable path. Salesforce's deployment engine does not consistently attribute coverage to dynamically instantiated classes, making `Type.forName()` an unreliable coverage mechanism in production deployments despite being architecturally elegant.

**Secondary approach (validate via spike first): generic test harness using `Type.forName()`.**

A single `ExtoleEventHandlerTest` class ships in the package and uses `Type.forName()` to instantiate any generated handler. If the spike confirms coverage is attributed correctly, this approach reduces org storage footprint (one test class instead of one per config). However do not treat this as the default until validated — the per-handler generated test class is the safe fallback and should be implemented regardless.

**Spike task (pre-build):** Run the spike defined in the v2 pre-flight doc. If `Type.forName()` produces coverage, the generic harness can supplement the per-handler tests. If not, per-handler tests are the sole coverage mechanism. Either way, per-handler test generation must be implemented.

---

## Data Model

### `Extole_Event_Config__mdt` (Custom Metadata Type)

| Field | Type | Notes |
|---|---|---|
| Config_Key | Text | Stable unique key used in generated artifact naming. Derived from developer name. |
| Config_Version | Number | Increments on each redeploy. Used in versioned class naming (_v2, _v3). |
| Event_Name | Text | Extole `event_name` value |
| Trigger_Object | Text | SFDC object API name |
| Trigger_Type | Picklist | CREATED, UPDATED, FIELD_EQUALS, FIELD_CHANGES |
| Trigger_Field | Text | API name of field (for FIELD_EQUALS / FIELD_CHANGES) |
| Trigger_Value | Text | Value to match (for FIELD_EQUALS) |
| Trigger_From_Value | Text | From value (for FIELD_CHANGES) |
| Trigger_To_Value | Text | To value (for FIELD_CHANGES) |
| Field_Mappings_JSON | Long Text | Serialized array of {extole_param, sfdc_field, static_value} |
| Apex_Class_Name | Text | Name of current active generated Apex class |
| Flow_Name | Text | Name of generated Flow |
| Status | Picklist | ACTIVE, INACTIVE, DRAFT, DEPLOY_FAILED |
| Deploy_Error | Long Text | Human-readable translated error message shown in UI |
| Deploy_Error_Raw | Long Text | Raw platform error from Tooling/Metadata API. Retained for support and debugging. |
| Last_Deployed | DateTime | Timestamp of last successful deploy |
| Deployed_By_User_Id | Text | SFDC user ID of admin who last deployed |
| Last_Tested_Record_Id | Text | ID of record used in most recent test preview |
| Active | Checkbox | Controls whether Flow is active |
| Last_Attempted_At | DateTime | Timestamp of most recent callout attempt |
| Last_Succeeded_At | DateTime | Timestamp of most recent successful callout (HTTP 200) |
| Last_Failed_At | DateTime | Timestamp of most recent failed callout |
| Last_Record_Id | Text | SFDC record ID from most recent callout attempt |
| Last_HTTP_Status | Number | HTTP status code from most recent Extole API response |
| Last_Response_Summary | Text | Brief summary of most recent Extole response (success or error message) |

**Last fire fields** are always populated for operational visibility — they do not require debug logging to be enabled. Verbose per-callout logging (full payload, response body, null field exclusions) remains opt-in via `Extole_Debug_Log__c`. This ensures the config row health indicator is a dependable operational surface regardless of logging settings.

---

## Deployment Architecture

**Tooling API via session-based auth:**
All Apex class deployment calls use the Tooling API from server-side Apex, authenticated via `UserInfo.getSessionId()`. No Connected App, Auth Provider, or second Named Credential required. The running admin's session is sufficient — they must have Author Apex permission.

**Metadata API for Flow deployment:**
Flow deployment uses the Metadata API — standard pattern for Flow deployment from Apex.

**Single Named Credential:**
Only the existing Extole API Named Credential from v1 is required. No additional credentials needed for deployment operations.

**Deployment is asynchronous:**
The configurator shows a "Deploying..." state with progress indicator and polls for completion. On success, status updates to ACTIVE. On failure, status updates to DEPLOY_FAILED with error detail.

**Edit/redeploy sequence:**
1. Increment `Config_Version`, derive new class name with version suffix
2. Deploy new Apex class via Tooling API
3. Deploy FlowDefinition with `activeVersionNumber=0` to deactivate old Flow version
4. Deploy updated Flow pointing to new Apex class
5. Activate new Flow version
6. Update `Extole_Event_Config__mdt` with new class name and version

## Logging

### `Extole_Event_Log__c` (Custom Object)

**Always on — not opt-in.** Auto-purges entries older than 90 days to prevent unbounded growth in orgs with high revision frequency. "Clear event log" action available in the configurator tab for manual cleanup.

| Field | Type | Notes |
|---|---|---|
| Config_Key | Text | References `Extole_Event_Config__mdt` |
| Event_Type | Picklist | See event types below |
| User_Id | Text | SFDC user who triggered the action |
| Timestamp | DateTime | Millisecond precision |
| Result | Picklist | SUCCESS, FAILED, CANCELLED, FOUND, NOT_FOUND, UNKNOWN |
| Detail | Long Text | Error message, campaign name, payload summary, etc. |
| Sync_Batch_Id | Text | Groups all log entries from a single deploy run |

**Event types logged:**

| Event Type | Trigger | Detail field |
|---|---|---|
| CONFIG_CREATED | Admin saves new config | Event name, object, trigger type |
| CONFIG_EDITED | Admin saves changes to existing config | Fields changed |
| CONFIG_DELETED | Admin confirms deletion | Result of safety check, action taken (Delete / Delete anyway / Deactivate) |
| DEPLOY_INITIATED | Admin clicks Deploy | Config key, version |
| DEPLOY_SUCCEEDED | Tooling/Metadata API confirms | Class name, flow name |
| DEPLOY_FAILED | Tooling/Metadata API returns error | Full error message, attempt count |
| FLOW_ACTIVATED | Flow activated post-deploy | Flow name, version |
| FLOW_DEACTIVATED | Admin deactivates or deletes | Flow name, triggered by user or system |
| SAFETY_CHECK_RUN | Delete initiated | Event name, duration, result (FOUND/NOT_FOUND/UNKNOWN), campaign name if found |
| SAFETY_CHECK_ACTION | Admin acts after safety check | Action taken: Delete, Delete anyway, Deactivate, Cancel |

**`CONFIG_DELETED` with action = "Delete anyway" after result = "FOUND" is a high-value audit event** — flags that an admin knowingly deleted an event that was in active use.

### Runtime Callout Logging (opt-in)

Generated Apex callout events go into `Extole_Debug_Log__c` — same object as v1, same opt-in per-config pattern. Off by default.

| Event | Logged |
|---|---|
| Callout fired | Event name, record ID, timestamp |
| Callout succeeded | HTTP 200, payload size |
| Callout failed | HTTP status, error body, retry attempt |
| Null fields excluded | Which fields were null on which record (debug only) |

---

## Delete Dependency Check

### Goal
Prevent accidental deletion of an event configuration that is still referenced by active Extole campaign logic.

### Deactivate
No dependency scan required. Deactivation is the safer, recoverable action and proceeds immediately. Optional inline note: "This event may still be referenced by existing Extole campaigns."

### Delete
Triggers a best-effort dependency check before confirming. The check is boolean — not exhaustive. The app only needs to know whether at least one active dependency exists, allowing a short-circuit on first match.

**Flow:**
1. Admin clicks Delete
2. Confirmation modal opens immediately
3. Modal shows "Checking Extole campaign usage…" while callout runs
4. App calls Extole API with the configured event name, retrieves campaign/build trigger data, scans `event_names` in active/published campaign triggers, stops on first match
5. Modal updates based on result:

| Result | Display | Primary action | Secondary action |
|---|---|---|---|
| NOT_FOUND | Normal delete confirmation | Delete | Cancel |
| FOUND | "This event is used by an active Extole campaign. Campaign: [campaignName]. Deleting it may break campaign behavior. Deactivation is recommended." | Deactivate | Delete anyway |
| UNKNOWN (API failed/timeout) | "We couldn't verify whether this event is in use by Extole campaigns. Deactivation is safer than deletion." | Deactivate | Delete anyway |

**API result shape:**
```json
{
  "status": "FOUND" | "NOT_FOUND" | "UNKNOWN",
  "campaignName": "optional first match name",
  "campaignId": "optional first match ID"
}
```

**Campaign state:** only active/published campaigns are treated as blocking-risk usage in v1. Draft, paused, archived, or inactive campaigns do not trigger the warning.

**UX notes:**
- Delete button is disabled while the check runs — admin cannot race ahead of the result. If the dependency check does not return within 10 seconds, the result is treated as UNKNOWN.
- "Delete anyway" is visually de-emphasized in FOUND and UNKNOWN states to steer toward the safe action without removing the escape hatch
- Campaign name is shown inline when available (FOUND state) so the admin has context, not just an abstract warning
- Checking state shows a spinner inline in the modal — no separate loading screen

**Future enhancement:** a "View usage" action that performs a full scan and lists all matching campaigns. Out of scope for v1.

**Dependency on Extole API:** requires that campaign trigger `event_names` are accessible via the Extole API. Confirm endpoint availability before build — if unavailable, the check always returns UNKNOWN and the UX defaults to the safer deactivation path.

---

## Preset Templates

Ship with the package as default `Extole_Event_Config__mdt` records in Draft state. Presets:

1. **Lead Created** — Lead, record created, maps Id, FirstName, LastName, Email, Company, AdvocateCode to `lead_created`
2. **Lead Converted** — Lead, IsConverted equals True, maps same fields to `lead_converted`
3. **Opportunity Closed/Won** — Opportunity, StageName equals Closed Won, maps Id, Name, Email to `opportunity_closedwon`

---

## Key Differences from v1

| Concern | v1 (Reporting) | v2 (Configurator) |
|---|---|---|
| Direction | Extole → SFDC | SFDC → Extole |
| Data flow | Pull (Extole API) | Push (Apex callout) |
| Primary user | Viewers + admin | Admin only |
| Generated artifacts | None | Apex class + Flow per event |
| External dependency | Extole Reporting API | Salesforce Tooling/Metadata API (session auth) |
| Named Credentials | 1 (Extole) | 1 (Extole — same credential) |

---

## Open Questions

1. **Tooling API availability in managed packages** — confirmed feasible in design. Session-based auth (`UserInfo.getSessionId()`) works from server-side Apex per documented patterns. No Connected App or second Named Credential required. Author Apex permission required on the installing admin. Package API Access must be configured to allow dynamic API calls. Architecture is sound but package-context behavior should be validated in a subscriber org spike before build — do not mistake architectural confidence for empirical validation.

2. **Governor limits on generated Apex** — resolved. Not a practical concern — each generated class is ~2-3KB against a 6MB limit. Generic test harness (`ExtoleEventHandlerTest`) ships in the package using `Type.forName()` for dynamic coverage. **Requires prototype validation — see Test Coverage Architecture.**

3. **Flow versioning** — resolved. Edit/redeploy uses FlowDefinition deactivation pattern (`activeVersionNumber=0`) before deploying new version. Stable and well-documented.

4. **Deletion behavior** — resolved. Flow deactivated immediately on config delete. Apex class retained as orphan, cleaned up via manual admin action in Settings to avoid triggering full test suite runs automatically.

5. **Connected App setup friction** — resolved. No Connected App required. Tooling API called from server-side Apex using `UserInfo.getSessionId()`. Only one Named Credential needed (existing Extole credential).

6. **Test coverage approach** — primary approach is per-handler generated test class (reliable, guaranteed). Secondary approach is generic `Type.forName()` harness (elegant, unconfirmed). Spike must validate whether `Type.forName()` produces coverage in production deployments. Per-handler test generation must be implemented regardless of spike outcome.
