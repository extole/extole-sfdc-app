# Extole SFDC App

Connects Salesforce to your Extole referral program. Syncs program KPIs into Salesforce and sends Salesforce record events to Extole to trigger referral actions.

---

## What it does

**KPI Dashboard** — Pulls report data from the Extole API on a configurable schedule (hourly, daily, or weekly) and displays it as metric tiles inside Salesforce. Admins choose which Extole reports to surface and how frequently to sync.

**Event Configurator** — Lets admins define record-triggered events that fire to Extole when Salesforce records change. For example: send an event to Extole when a Lead is created, or when an Opportunity moves to Closed Won. No code required — the app generates and deploys the necessary Salesforce Flow automatically.

---

## What gets installed

**Custom Objects**

| Object | Purpose |
|---|---|
| `Extole_App_Settings__c` | Org-wide configuration (sync cadence, notifications, feature toggles) |
| `Extole_Report_Config__c` | Admin-defined list of Extole reports to sync |
| `Extole_Report_Snapshot__c` | Latest synced values from each report |
| `Extole_Sync_Log__c` | Audit log of every sync attempt |
| `Extole_Event_Cfg__c` | Event trigger configurations created in the Event Configurator |
| `Extole_Event_Log__c` | Audit log of every event fired to Extole |
| `Extole_Debug_Log__c` | Optional detailed debug logs for troubleshooting |

**Permission Sets**

| Permission Set | Assign to |
|---|---|
| `Extole_App_Admin` | Admins who configure the integration |
| `Extole_App_Viewer` | Users who need read access to the KPI Dashboard |
| `Extole_API_Access` | System — grants access to the Extole API credential |

**App and Tabs** — A Lightning app with three tabs: KPI Dashboard, List View, and Settings. The Event Configurator is embedded in Settings.

**Apex Classes** — Backend logic for syncing, event handling, and Tooling API integration.

**Custom Metadata Type** (`Extole_Event_Config__mdt`) — Stores built-in event templates: Lead Created, Lead Converted, Opportunity Closed Won.

---

## Auth model

The app uses two Named Credentials for all external callouts — no tokens are stored in Apex code or custom fields.

**Extole API** (`Extole_API`) — Custom External Credential using a long-lived bearer token generated from the Extole Security Center. Used by the sync job and event handlers to call `https://my.extole.com`.

**Salesforce Tooling API** (`Extole_Tooling`) — OAuth External Credential backed by a Connected App. Used by the Event Configurator to deploy generated Flows into the org. Requires a one-time admin OAuth authorization after setup.

---

## Ongoing maintenance

- **Sync cadence** — Change in Settings → Sync Management. The scheduled job is automatically re-registered on save.
- **Adding KPIs** — Settings → Report Configuration → Add Report. New tiles appear on the KPI Dashboard after the next sync.
- **Event configs** — Settings → Event Configurations. Create, edit, deactivate, or delete event triggers. Before deleting, the app calls the Extole API to check whether the event is still referenced by an active campaign. Deleting a config also removes the associated Flow automatically.
- **Failure notifications** — Settings → Notifications. Enable email alerts after N consecutive sync failures.
- **Debug logging** — Settings → Debug. Enable for detailed per-sync logs. Disable when not actively troubleshooting to avoid log volume.
- **Log retention** — Sync logs, event logs, and debug logs are automatically purged after 30 days on each sync run.

---

## Installation

See [INSTALL.md](INSTALL.md) for step-by-step setup instructions.
