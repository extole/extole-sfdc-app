# Extole SFDC App

Connects Salesforce to your Extole referral program. Syncs program KPIs into Salesforce and sends Salesforce record events to Extole to trigger referral actions.

---

## What it does

**Program Analytics** — Per-program funnel, time-series chart, and promotion/channel breakdown from the Extole summary report.

**KPI Dashboard** — Metric tiles pulled from the Extole API on a configurable schedule (hourly, daily, or weekly); admins choose which reports to surface.

**Event Configurator** — Define record-triggered events that fire to Extole when Salesforce records change (e.g. a Lead created, an Opportunity closing). No code required — the app generates and deploys the underlying Flow automatically.

**Manage Audiences** — Pushes members of a Salesforce report into an Extole audience (by email) on a configurable sync cadence, for campaign targeting and email promotions.

**Share Link Backfill** — Bulk-enrolls existing Contacts and Leads into Extole and writes their share links back to Salesforce. Audiences can be a Closed/Won opportunity filter, a date range, or a custom Salesforce report.

**List View** — A configurable list of Contacts or Leads filtered by a chosen field/value (e.g. by share-link source) for at-a-glance attribution review.

**Receive Events** — Accepts inbound webhooks from Extole (e.g. reward earned) and writes mapped fields back onto the matching Contact or Lead.

**Person Card** — A Lightning component on the Lead and Contact record pages surfacing that person's Extole share links, referred friends, rewards, and inbound referrer attribution.

---

## What gets installed

**Custom Objects**

| Object | Purpose |
|---|---|
| `Extole_App_Settings__c` | Org-wide configuration (sync cadence, notifications, feature toggles) |
| `Extole_Report_Config__c` | Admin-defined list of Extole reports to sync |
| `Extole_Report_Snapshot__c` | Latest synced values from each report |
| `Extole_Sync_Log__c` | Audit log of every KPI report sync attempt |
| `Extole_Event_Cfg__c` | Event trigger configurations created in the Event Configurator |
| `Extole_Event_Log__c` | Audit trail of event configuration lifecycle actions (deploys, activations, failures) |
| `Extole_Event_Fire_Log__c` | Runtime log of every Extole event fired by configured triggers |
| `Extole_Backfill_Log__c` | Audit log of share link backfill jobs |
| `Extole_Person_Snapshot__c` | Cached Extole person data for Contacts and Leads |
| `Extole_Debug_Log__c` | Optional detailed debug logs for troubleshooting |
| `Extole_Audience_Cfg__c` | Admin-defined Salesforce report → Extole audience sync configurations |
| `Extole_Audience_Sync_Log__c` | Audit log of every audience sync attempt |
| `Extole_Writeback_Cfg__c` | Field-mapping rules for writing inbound Extole webhook events back to Contact/Lead fields |
| `Extole_Writeback_Log__c` | Log of every inbound Extole webhook event received and its write-back outcome |

**Permission Sets**

| Permission Set | Assign to |
|---|---|
| `Extole_App_Admin` | Admins configuring the integration (reports, audiences, events, writeback rules, credentials) |
| `Extole_App_Viewer` | Users who need read access to Program Analytics, KPI Dashboard, and List View |
| `Extole_API_Access` | System/integration users — grants access to the Extole API credential only |

**App and Tabs** — A Lightning app with nine tabs: Program Analytics, KPI Dashboard, List View, Manage Share Links, Configure Events, Configure KPIs, Manage Audiences, Manage List View, and Receive Events.

**Apex Classes** — Backend logic for syncing, event handling, and Tooling/webhook integration.

**Custom Metadata Type** (`Extole_Event_Config__mdt`) — Stores built-in event templates: Lead Created, Lead Converted, Opportunity Closed Won.

---

## Auth model

The app uses two Named Credentials for all external callouts — no tokens are stored in Apex code or custom fields.

**Extole API** (`Extole_API`) — Custom External Credential using a long-lived bearer token generated from the Extole Security Center. Used by the sync job and event handlers to call `https://my.extole.com/security-center`.

**Salesforce Tooling API** (`Extole_Tooling`) — OAuth External Credential backed by a Connected App. Used by the Event Configurator to deploy generated Flows into the org. Requires a one-time admin OAuth authorization after setup.

**Inbound webhooks (Receive Events)** — Reversed direction: Extole calls *into* Salesforce at a `@RestResource` endpoint (`/services/apexrest/extole/events`), authenticated via a Connected App using OAuth 2.0 Client Credentials. Its Consumer Key/Secret live on the Extole side (as the webhook's `CLIENT_KEY` setting), not in this package.

---

## Ongoing maintenance

- **Sync cadence** — Change in Configure KPIs → Sync Management. The scheduled job is automatically re-registered on save.
- **Adding KPIs** — Configure KPIs → Add Report. New tiles appear on the KPI Dashboard after the next sync.
- **Event configs** — Configure Events. Create, edit, deactivate, or delete event triggers. Before deleting, the app calls the Extole API to check whether the event is still referenced by an active campaign. Deleting a config also removes the associated Flow automatically.
- **Failure notifications** — Configure KPIs → Sync Management. Enable email alerts after N consecutive sync failures.
- **Debug logging** — Configure Events → Debug. Enable for detailed per-sync logs. Disable when not actively troubleshooting to avoid log volume.
- **Backfilling share links** — Manage Share Links. Pick an audience (Closed/Won opps, date range, or custom report), choose the target field, and run. Progress and results are recorded in the backfill log.
- **List View setup** — Manage List View. Choose the object, filter field/value, columns, and start date for the List View tab.
- **Audience sync** — Manage Audiences. Pick a Salesforce report and sync cadence; the sync log on the same tab records each run's outcome.
- **Receive Events / writeback rules** — Receive Events. Map incoming webhook event fields to Contact or Lead fields; the event log on the same tab records every inbound webhook and its outcome.
- **Log retention** — Sync logs, event logs, audience sync logs, writeback logs, and debug logs are automatically purged after 30 days on each sync run.

---

## Installation

See [INSTALL.md](INSTALL.md) for step-by-step setup instructions.
