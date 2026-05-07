# Extole SFDC App

Connects Salesforce to your Extole referral program. Syncs program KPIs into Salesforce and sends Salesforce record events to Extole to trigger referral actions.

---

## What it does

**KPI Dashboard** — Pulls report data from the Extole API on a configurable schedule (hourly, daily, or weekly) and displays it as metric tiles inside Salesforce. Admins choose which Extole reports to surface and how frequently to sync.

**Event Configurator** — Lets admins define record-triggered events that fire to Extole when Salesforce records change. For example: send an event to Extole when a Lead is created, or when an Opportunity moves to Closed Won. No code required — the app generates and deploys the necessary Salesforce Flow automatically.

**Share Link Backfill** — Bulk-enrolls existing Contacts and Leads into Extole and writes their share links back to Salesforce. Audiences can be a Closed/Won opportunity filter, a date range, or a custom Salesforce report.

**List View** — A configurable list of Contacts or Leads filtered by a chosen field/value (e.g. by share-link source) for at-a-glance attribution review.

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

**Permission Sets**

| Permission Set | Assign to |
|---|---|
| `Extole_App_Admin` | Admins who configure the integration |
| `Extole_App_Viewer` | Users who need read access to the KPI Dashboard |
| `Extole_API_Access` | System — grants access to the Extole API credential |

**App and Tabs** — A Lightning app with six tabs:

| Tab | Purpose |
|---|---|
| KPI Dashboard | Metric tiles for synced Extole reports |
| List View | Configurable Contact/Lead list filtered by an attribution field |
| Manage Share Links | Bulk backfill share links onto existing Contacts and Leads |
| Configure Events | Event Configurator, connection test, configuration history, fire log, and debug logging |
| Configure KPIs | KPI report configuration, sync schedule, notifications, and import log |
| Manage List View | Settings for which records and columns appear on the List View tab |

**Apex Classes** — Backend logic for syncing, event handling, and Tooling API integration.

**Custom Metadata Type** (`Extole_Event_Config__mdt`) — Stores built-in event templates: Lead Created, Lead Converted, Opportunity Closed Won.

---

## Auth model

The app uses two Named Credentials for all external callouts — no tokens are stored in Apex code or custom fields.

**Extole API** (`Extole_API`) — Custom External Credential using a long-lived bearer token generated from the Extole Security Center. Used by the sync job and event handlers to call `https://my.extole.com/security-center`.

**Salesforce Tooling API** (`Extole_Tooling`) — OAuth External Credential backed by a Connected App. Used by the Event Configurator to deploy generated Flows into the org. Requires a one-time admin OAuth authorization after setup.

---

## Ongoing maintenance

- **Sync cadence** — Change in Configure KPIs → Sync Management. The scheduled job is automatically re-registered on save.
- **Adding KPIs** — Configure KPIs → Add Report. New tiles appear on the KPI Dashboard after the next sync.
- **Event configs** — Configure Events. Create, edit, deactivate, or delete event triggers. Before deleting, the app calls the Extole API to check whether the event is still referenced by an active campaign. Deleting a config also removes the associated Flow automatically.
- **Failure notifications** — Configure KPIs → Sync Management. Enable email alerts after N consecutive sync failures.
- **Debug logging** — Configure Events → Debug. Enable for detailed per-sync logs. Disable when not actively troubleshooting to avoid log volume.
- **Backfilling share links** — Manage Share Links. Pick an audience (Closed/Won opps, date range, or custom report), choose the target field, and run. Progress and results are recorded in the backfill log.
- **List View setup** — Manage List View. Choose the object, filter field/value, columns, and start date for the List View tab.
- **Log retention** — Sync logs, event logs, and debug logs are automatically purged after 30 days on each sync run.

---

## Installation

See [INSTALL.md](INSTALL.md) for step-by-step setup instructions.
