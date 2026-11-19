# Extole SFDC App

Connects Salesforce to your Extole referral program. Syncs program KPIs into Salesforce and sends Salesforce record events to Extole to trigger referral actions.

---

## What it does

**Program Analytics** — Per-program funnel, time-series chart, and promotion/channel breakdown from the Extole summary report.

**KPI Dashboard** — Metric tiles pulled from the Extole API on a configurable schedule (hourly, daily, or weekly); admins choose which reports to surface.

**Event Configurator** — Define record-triggered events that fire to Extole when Salesforce records change (e.g. a Lead created, an Opportunity closing). No code required — the app generates and deploys the underlying Flow automatically.

**Manage Audiences** — Pushes members of a Salesforce report into an Extole audience (by email) on a configurable sync cadence, for campaign targeting and email promotions.

**Share Link Backfill** — Bulk-enrolls existing Contacts and Leads into Extole and writes their share links back to Salesforce. Audiences can be a Closed/Won opportunity filter, a date range, or a custom Salesforce report.

**Receive Extole Events** — Accepts inbound webhooks from Extole (e.g. reward earned) and writes mapped fields back onto the matching Contact or Lead.

**Person Card** — The _Extole Referrals_ card for Lead, Contact and Person Account record pages. It shows that person's share links, the friends they referred with each friend's progress and reward, and who referred them. Large friend lists load a few at a time, and the Expand icon opens a searchable list.

**Offers Card** — The _Extole Offers_ card for the same record pages. It shows the Extole offers a person is in that aren't referrals, grouped by program with each reward and its steps, and hides itself when there are none. It isn't placed on a page automatically; an admin adds it from the Lightning App Builder.

---

## What gets installed

**Custom Objects**

| Object                        | Purpose                                                                                   |
| ----------------------------- | ----------------------------------------------------------------------------------------- |
| `Extole_App_Settings__c`      | Org-wide configuration (sync cadence, notifications, feature toggles)                     |
| `Extole_Report_Config__c`     | Admin-defined list of Extole reports to sync                                              |
| `Extole_Report_Snapshot__c`   | Latest synced values from each report                                                     |
| `Extole_Sync_Log__c`          | Audit log of every KPI report sync attempt                                                |
| `Extole_Event_Cfg__c`         | Event trigger configurations created in the Event Configurator                            |
| `Extole_Event_Log__c`         | Audit trail of event configuration lifecycle actions (deploys, activations, failures)     |
| `Extole_Event_Fire_Log__c`    | Runtime log of every Extole event fired by configured triggers                            |
| `Extole_Backfill_Log__c`      | Audit log of share link backfill jobs                                                     |
| `Extole_Debug_Log__c`         | Optional detailed debug logs for troubleshooting                                          |
| `Extole_Audience_Cfg__c`      | Admin-defined Salesforce report → Extole audience sync configurations                     |
| `Extole_Audience_Sync_Log__c` | Audit log of every audience sync attempt                                                  |
| `Extole_Writeback_Cfg__c`     | Field-mapping rules for writing inbound Extole webhook events back to Contact/Lead fields |
| `Extole_Writeback_Log__c`     | Log of every inbound Extole webhook event received and its write-back outcome             |

**Permission Sets**

| Permission Set               | Assign to                                                                                                                                                                                                  |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Extole_App_Admin`           | Admins configuring the integration (reports, audiences, events, writeback rules, credentials)                                                                                                              |
| `Extole_App_Viewer`          | Users who need read access to Program Analytics and the KPI Dashboard                                                                                                                                      |
| `Extole_API_Access`          | System/integration users — grants access to the Extole API credential only                                                                                                                                 |
| `Extole_Webhook_Integration` | The **Run As** user of the Receive Extole Events Client Credentials app ([Salesforce CRM Integration](https://docs.extole.com/technical/partners/crm/extole-to-salesforce-crm#salesforce-crm-integration)) |

**App and Tabs** — A Lightning app with seven tabs: Program Analytics, KPI Dashboard, Manage Share Links, Send Extole Events, Receive Extole Events, Configure KPIs, and Manage Audiences.

**Apex Classes** — Backend logic for syncing, event handling, and Tooling/webhook integration.

**Custom Metadata Type** (`Extole_Event_Config__mdt`) — Stores built-in event templates: Lead Created, Lead Converted, Opportunity Closed Won.

---

## Auth model

The app uses two Named Credentials for all external callouts — no tokens are stored in Apex code or custom fields.

**Extole API** (`Extole_API`) — Custom External Credential using a long-lived bearer token generated from the Extole Security Center. Used by the sync job and event handlers to call `https://api.extole.io`.

**Salesforce Tooling API** (`Extole_Tooling`) — OAuth External Credential backed by a Connected App. Used by the Event Configurator to deploy generated Flows into the org. Requires a one-time admin OAuth authorization after setup.

**Inbound webhooks (Receive Extole Events)** — Reversed direction: Extole calls _into_ Salesforce at a `@RestResource` endpoint (`/services/apexrest/extole/events`), authenticated via a Connected App using OAuth 2.0 Client Credentials. Its Consumer Key/Secret live on the Extole side (as the **Salesforce OAuth Credentials** setting of the **Salesforce CRM** integration), not in this package.

---

## Ongoing maintenance

- **Sync cadence** — Change in Configure KPIs → Sync Management. The scheduled job is automatically re-registered on save.
- **Adding KPIs** — Configure KPIs → Add KPI. New tiles appear on the KPI Dashboard after the next sync.
- **Event configs** — Send Extole Events. Create, edit, deactivate, or delete event triggers. Before deleting, the app calls the Extole API to check whether the event is still referenced by an active campaign. Deleting a config also removes the associated Flow automatically.
- **Failure notifications** — Configure KPIs → Sync Management. Enable email alerts after N consecutive sync failures.
- **Debug logging** — Send Extole Events → Debug. Enable for detailed per-sync logs. Disable when not actively troubleshooting to avoid log volume.
- **Backfilling share links** — Manage Share Links. Pick an audience (Closed/Won opps, date range, or custom report), choose the target field, and run. Progress and results are recorded in the backfill log.
- **Audience sync** — Manage Audiences. Pick a Salesforce report and sync cadence; the sync log on the same tab records each run's outcome.
- **Receive Extole Events / writeback rules** — Receive Extole Events. Map incoming webhook event fields to Contact or Lead fields; the event log on the same tab records every inbound webhook and its outcome.
- **Log retention** — Sync logs, event logs, event fire logs, audience sync logs, writeback logs, and debug logs are automatically purged after 30 days by a dedicated nightly job, independent of KPI sync or any other feature being configured.

---

## Installation

See the [install guide](https://docs.extole.com/technical/partners/crm/extole-to-salesforce-crm) for step-by-step setup instructions, including the Person Accounts section for orgs on Financial Services Cloud.
