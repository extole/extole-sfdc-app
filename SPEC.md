# Extole SFDC App – Spec v4

## Overview

A Salesforce managed package that surfaces Extole program data inside a client's SFDC org. Designed for any Extole client whose team uses Salesforce — sales teams, account managers, customer success, or anyone who needs visibility into program performance without logging into Extole directly.

The app is a consumer of Extole's existing reporting catalog — it does not create or modify reports.

---

## App Structure

A custom SFDC app with up to three tabs, rendered based on config:

| Tab | Default State | Config Flag |
|---|---|---|
| Program Overview | Always visible | — |
| Lead Attribution | Hidden until enabled | `Show_Lead_Attribution__c` |
| Settings | Always visible (admin only) | — |

---

## Tab 1: Program Overview

Displays program-level aggregate metrics pulled from Extole via the Reporting API. Metrics are defined entirely by config — the tab renders whatever report snapshots exist for the org, styled using Salesforce Lightning Design System (SLDS) components.

**Layout:** metric tiles in a 3-column grid, each showing:
- Display label (up to 3 lines, 120 char max, ellipsis truncation with full text on hover tooltip)
- Value
- Period label ("last 30 days" / "last 90 days" / "year to date")
- Trend indicator where chart is configured ("↑ 12% vs prior 30d")
- Sparkline or bar chart where configured (weekly granularity)
- As-of date with stale indicator if older than 48hrs past expected refresh
- Orphan indicator if backing config record has been deleted
- "View in Extole →" link where available (see Tile click-through below)

**Date range toggle:** users can switch between Rolling 30 / Rolling 90 / YTD without going into Settings. Toggle is display-only — all three ranges are pre-computed at sync time and stored as separate snapshot records per config. Switching ranges is instant, no API call on toggle.

**Chart rendering:** Sparkline and bar charts are rendered as inline SVGs with coordinates and path data computed in JavaScript — no third-party charting libraries. Keeps the package lightweight and avoids SLDS compliance issues.

**Stale indicator timezone note:** `As_Of_Date` is stored in UTC. Stale threshold calculation must account for timezone conversion between UTC and the SFDC org's configured timezone to avoid false stale indicators.

**Prior period sync note:** time series configs require 2× API calls per sync (current + prior period). Nightly sync cadence recommended for orgs with many time series configs.

**Empty states:** use `lightning-illustration` component for empty and no-data states throughout the app to maintain native SFDC feel.

**Config panel:** presented as a modal (not a side drawer) to provide focus and accommodate the depth of configurable fields.

**MDT access:** LWCs cannot access Custom Metadata directly. Since report config is now stored in `Extole_Report_Config__c` (Custom Object), standard `@AuraEnabled` Apex methods with SOQL are used for all config reads and writes — no Metadata API wrapper required.

**Chart types:**
- None — value, period label, and as-of date only
- Sparkline — trend line over selected window. Footer shows week count ("4 weeks", "13 weeks", "~52 weeks")
- Bar — weekly volume bars, current week highlighted. Footer shows "weekly"

**Trend indicator** (Sparkline and Bar tiles only): percentage change vs prior equivalent period ("vs prior 30d", "vs prior 90d", "vs prior year"). Requires a second report execution per sync cycle for prior period data.

**Soft cap:** 16 active report configs maximum. Settings UI warns if approaching limit. This cap is set deliberately to stay within Salesforce's 100 HTTP callout limit per transaction: 16 configs × 3 date ranges × 2 calls (current + prior period) = 96 callouts. Do not raise this cap without moving to a Queueable chain architecture.

**Tile click-through:** each tile includes a "View in Extole →" link with tooltip "View full report in Extole" opening in a new tab. The link points to the specific report instance from the most recent successful sync — not the generic reports page.

Link construction:
- Primary: use `View_URL` persisted from the most recent successful report run response
- Fallback: construct `https://my.extole.com/reports/view?client_id=<Client_Id>#<Report_Id>` from persisted `Client_Id` and `Report_Id`
- Both values are written to the snapshot record during each successful sync — the link always reflects the most recent run
- If neither value is available, hide the link entirely
- The link is a navigational URL only — the user must have an active Extole session and appropriate permissions to view the report

**Stale indicator logic:**
- Stale = `Next_Expected_Sync__c` < now — calculated by reading the field, not by computing cadence in the LWC
- Written by sync job after each successful upsert: current timestamp + configured cadence
- Manual sync resets `Next_Expected_Sync__c` from the new completion time
- Failed sync: `Next_Expected_Sync__c` is not updated — field ages out naturally, triggering stale indicator
- LWC reads the field directly — no datetime arithmetic in the UI layer

**Tile states:**

| Status | Visual treatment |
|---|---|
| Current | Normal rendering |
| Stale | As-of date in warning color |
| Sync failed | Error icon + "Failed [date]" in danger color. Prior value shown if available, em dash if not |
| Orphaned | Entire tile at 50% opacity. Footer: "No longer configured" |
| Pending first sync | Full-tile muted message: "Sync pending — data will appear after the first sync." |

**Full-tab states:**

| Condition | Audience | Display |
|---|---|---|
| Token invalid | Admin | "Unable to connect to Extole. Please check your API token in Settings." |
| Last full sync failed | Admin | Banner above tiles: "Last sync failed on [date]. Contact your admin." Tiles show last known values |
| No config, no snapshots | Admin | Guided setup prompt |
| No config, no snapshots | Viewer | `lightning-illustration` + ghost tile grid + "Your Extole program data will appear here once your admin completes setup." |

---

## Tile Design Specification

Tiles are rendered using SLDS components. Each tile is a card with consistent structure regardless of chart type.

### Anatomy (top to bottom)

1. **Display Label** — 11px, uppercase, letter-spaced, muted color. Max 120 characters. Up to 3 lines, ellipsis truncation on overflow. Full label shown in hover tooltip.
2. **Value** — 28px, weight 500, primary text color. Single line.
3. **Period / trend row** — 12px, tertiary text color:
   - No chart: period label only ("last 30 days" / "last 90 days" / "year to date")
   - Sparkline or Bar: trend indicator + prior period label ("↑ 12% vs prior 30d"). Trend up = success color, trend down = danger color.
4. **Chart** (if configured) — 48px tall, full tile width:
   - Sparkline: SVG path with gradient fill. Stroke color: Extole green (`#1D9E75`). Week count label centered below.
   - Bar: SVG bars, weekly granularity. Current week at full opacity, prior weeks at 25% opacity. Fill color: Extole green. "weekly" label centered below.
5. **Footer** — 12px, tertiary color. As-of date. Modified by status variant.
6. **"View in Extole →"** — 12px link, shown when `view_url` is available. Opens in new tab.

### Viewer Empty State

Two elements stacked vertically:

1. **Illustration** — inline SVG at 40-50% opacity. Shows two overlapping card shapes with placeholder content bars, with a small checkmark circle in the center. Below it: title "Your Extole program data will appear here" (15px, weight 500, secondary color) and body "Once your admin completes setup, this tab will show live metrics from your Extole program." (13px, tertiary color, max-width 320px, centered).

2. **Ghost tile grid** — three tiles in the standard 3-column grid at 40% opacity with `pointer-events: none`. All content replaced by rounded rectangle placeholders (muted border color, no fill): a short label bar, a taller value bar, a narrow period bar. The center tile additionally shows a ghost bar chart — 7 bars of varying heights, same muted style. No action button — viewers cannot configure the app.

### Grid

3-column grid, 12px gap. Collapses to 2 columns on narrower viewports. Soft cap of 20 tiles enforced in config.

### Range Toggle

Sits above the tile grid. Three buttons: Rolling 30 / Rolling 90 / YTD. Active state: secondary background, primary border, weight 500. Switching range reads from pre-computed snapshots — no API call.

---

## Tab 2: Lead Attribution

Displays RAF-sourced lead data queried natively from SFDC. Renders only when `Show_Lead_Attribution__c` = true and RAF lead field/value are configured. All visuals rendered in SLDS.

**Default layout:**
- RAF leads created (period)
- RAF lead conversion rate
- Pipeline value attributed to RAF leads
- RAF vs. non-RAF conversion rate comparison

**Data source:** native SOQL query against Lead object, filtered by configured field/value.

**Tracking notice:** displays "Tracking since [RAF_Tracking_Start_Date__c]" only when date is configured. Omitted if blank.

**Tab states:**

| Condition | Display |
|---|---|
| Feature disabled | Tab not visible |
| No tagged leads yet | "RAF leads will appear here once your Extole integration begins tagging leads in Salesforce." |
| SOQL query error | "Unable to load lead data. Contact your admin." |

---

## Tab 3: Settings

Admin-facing configuration UI. Requires `Extole_App_Admin` permission set. All interactions styled in SLDS.

---

### Section 1: Connection

| Field | Type | Notes |
|---|---|---|
| Extole API Token | Named Credential | Stored securely, never displayed in UI |
| Connection Status | Read-only indicator | Shows report count returned on success, specific error on failure |

One token per org. Multiple Extole accounts not supported in v1.

Named Credential access restricted to Apex integration context — not directly accessible by viewer-level users.

---

### Section 2: Report Configuration

A report picker backed by `GET /v6/report-types`. Admins select from pre-configured reports that already exist in the client's Extole account. No report creation from SFDC.

The picker calls `GET /v6/report-types` live on open — no local cache. Reports created or modified in My Extole are immediately available in the picker on next open.

#### Report Picker

**API query parameters used:**
- `visibility` = PUBLIC
- `exclude_tags` = internal:flag:archived, internal:flag:ending, internal:category:Legacy
- `search_query` (user-entered)
- `limit` / `offset` for pagination

**Default filter on open:** Performance & Metrics category pre-selected. Shown as a dismissible filter tag with a count ("Showing 4 of 42 reports"). Admin can clear the tag or change the category dropdown to broaden. This prevents the full catalog from rendering on open and surfaces the most relevant reports first.

**Client-side filters applied after fetch:**
- Only show reports where `formats` includes JSON
- Only show `type` of CONFIGURED, SPARK, or SQL — DASHBOARD excluded in v1

**Picker columns:**

| Field | Source | Notes |
|---|---|---|
| Display Name | `display_name` | |
| Description | `description` | |
| Speed | `type` | SQL only — shows ⚡ Fast badge. No badge for CONFIGURED or SPARK. |

#### Execution Eligibility Rules

Before a report can be saved to config, it must pass all of the following:
- `formats` includes JSON
- `preview_columns` contains at least one column
- All `is_required` parameters either have a `default_value` or an admin-specified override
- `type` is not DASHBOARD

#### Report Detail / Config Panel

When a report is selected, a detail modal opens:

**Read-only info:**
- `display_name`, `description`, `executor_type`
- `preview_columns` — table of columns with `name`, `sample_value`, `note`
- `parameters` — read-only list of name, type, default, required flag

**Admin-configurable fields:**

| Field | Type | Notes |
|---|---|---|
| Display Label | Text (max 120 chars) | Defaults to `display_name`. Up to 3 lines on tile, ellipsis truncation, tooltip on overflow. |
| Value Column | Picklist | Populated from `preview_columns` |
| Aggregation | Picklist | FIRST_ROW, SUM, COUNT. Default: FIRST_ROW. SUM only available when `sample_value` is numeric. COUNT = row count. |
| Chart Type | Picklist | None, Sparkline, Bar. Default: None. Sparkline and Bar require Time Series data mode. |
| Data Mode | Picklist | Single Value, Time Series. Auto-set to Time Series when Chart Type is Sparkline or Bar. Hidden from admin. |
| Date Range | Picklist | Rolling 30 / Rolling 90 / YTD. All three synced at runtime for toggle support. Default: Rolling 90 |
| Display Order | Number | Controls tile order |
| Parameter Overrides | Long Text (JSON) | Reserved for future use. No UI in v1. |
| Active | Checkbox | Default: true |

#### Execution Mapping

When the sync job runs a configured report, it constructs the `POST /v4/reports` request as follows:
- `name` → `Report_Name` from config
- `format` → JSON (always)
- `parameters.date_range` → derived from configured `Date_Range`
- All other parameters → passed using `default_value` from `ReportTypeResponse`
- Parameter overrides → serialized from `Parameter_Overrides_JSON` if present

Reports with required parameters that have no default and no override are ineligible for sync and flagged in the sync log.

---

### Section 3: Lead Attribution

| Field | Type | Notes |
|---|---|---|
| Show Lead Attribution Tab | Checkbox | Default: false |
| RAF Lead Field | Text | Default: `LeadSource` |
| RAF Lead Value | Text | Default: `Referral` |
| Tracking Start Date | Date | Displayed on Lead Attribution tab |

---

### Section 4: Sync Management

| Field | Type | Notes |
|---|---|---|
| Sync Cadence | Picklist | Nightly / Every 12hrs / Every 6hrs. Default: Nightly |
| Last Sync | Read-only | Timestamp of most recent completed sync |
| Sync Now | Button | Triggers full manual sync |
| Sync Log | Read-only table | Recent entries from `Extole_Sync_Log__c` |
| Notify on Sync Failure | Checkbox | Default: true. Sends email when sync fails consecutively. |
| Notify After N Failures | Number | Default: 2. Prevents single missed sync from triggering notification. |
| Failure Notification Email | Text | Defaults to installing admin email. Overridable. |

**Sync failure notification:** when the sync job fails N consecutive times (per config), it sends an outbound email to the configured address. Subject: `[Extole for Salesforce] Sync failure — action required`. Body includes org name, last successful sync timestamp, error summary from most recent failure, and a link to the Settings sync log. Implemented via `Messaging.sendEmail()` in the sync job Apex — same pattern as post-install notification. Manual sync success resets the consecutive failure counter.

**Orphan reconciliation:** table showing all `Extole_Report_Snapshot__c` records alongside config status (Active / Inactive / Orphaned). Includes "Clear Orphaned Data" action. Orphan detection runs during each scheduled sync by comparing active `Extole_Report_Config__c` record IDs against snapshot `Config_Id` values, and on-demand via the reconciliation view.

**Settings tab states:**

| Condition | Display |
|---|---|
| Token missing | Step 1 setup prompt |
| Token invalid | Red indicator with specific API error |
| Report picker load failure | "Unable to load reports from Extole. Check your connection." with retry |
| Config validation failure | Inline field-level errors |
| Single report test sync failure | Inline error with HTTP status and message |

---

## Data Model

### `Extole_Report_Snapshot__c` (Custom Object)

One record per (config, date_range) — latest wins. Historical entries retained in `Extole_Sync_Log__c`.

| Field | Type | Notes |
|---|---|---|
| Label | Text | Copied from config at sync time |
| Value | Text | Extracted from report output |
| Prior_Period_Value | Text | For trend indicator calculation |
| Time_Series_JSON | Long Text | Weekly data points for chart rendering |
| Report_Name | Text | `name` from ReportTypeResponse |
| Executor_Type | Text | SPARK, SQL, CONFIGURED |
| As_Of_Date | DateTime | Timestamp of successful sync |
| Date_Range | Text | Rolling 30, Rolling 90, or YTD |
| Display_Order | Number | Copied from config |
| Chart_Type | Text | None, Sparkline, Bar |
| Next_Expected_Sync | DateTime | Written by sync job after each successful upsert. Set to current timestamp + configured cadence. Used by LWC for stale indicator — simpler than recalculating at render time. Queryable directly for support diagnostics. |
| Config_Id | Text | ID of the parent `Extole_Report_Config__mdt` record |
| View_URL | Text | `view_url` from Extole report API response. Used for tile click-through. |
| Report_Id | Text | Extole report ID. Used to construct fallback deep link. |
| Client_Id | Text | Extole client ID. Used to construct fallback deep link. |

Uniqueness rule: (Config_Id, Date_Range) — upserted on each sync cycle. Orphan detection compares active config IDs against snapshot `Config_Id` values — any snapshot whose `Config_Id` no longer matches an active config is marked ORPHANED.

### `Extole_Report_Config__c` (Custom Object)

Stores report configuration. One record per configured metric tile. Uses a Custom Object rather than Custom Metadata Type — standard Apex DML makes the LWC-based admin UI simpler to build and maintain without requiring Metadata API wrappers for writes. Records do not promote across sandboxes automatically (unlike CMDTs) but this is acceptable since config is set up per org during onboarding.

| Field | Type | Notes |
|---|---|---|
| Report_Name | Text | |
| Report_Type | Text | CONFIGURED, SPARK, SQL |
| Executor_Type | Text | For polling strategy |
| Display_Label | Text (120) | |
| Value_Column | Text | |
| Aggregation | Picklist | FIRST_ROW, SUM, COUNT |
| Chart_Type | Picklist | None, Sparkline, Bar |
| Data_Mode | Picklist | Single Value, Time Series |
| Date_Range | Picklist | Rolling 30 / Rolling 90 / YTD |
| Display_Order | Number | |
| Parameter_Overrides_JSON | Long Text | Reserved, no UI in v1 |
| Active | Checkbox | |

### `Extole_Sync_Log__c` (Custom Object)

| Field | Type |
|---|---|
| Report_Name | Text |
| Date_Range | Text |
| Executor_Type | Text |
| Status | Picklist (SUCCESS, FAILED, SKIPPED) |
| Sync_Timestamp | DateTime (millisecond precision) |
| Value_Extracted | Text |
| HTTP_Status_Code | Number |
| Poll_Attempts | Number |
| Error_Message | Text |
| Sync_Batch_Id | Text |

### `Extole_Debug_Log__c` (Custom Object)

Off by default. Enabled globally or per report in Settings. Auto-purges after 7 days.

| Field | Type |
|---|---|
| Report_Name | Text |
| Log_Timestamp | DateTime (millisecond precision) |
| Event_Type | Text |
| Detail | Long Text |
| Sync_Batch_Id | Text |

---

## Background Sync

Scheduled Apex job runs on configured cadence (default: nightly, 2am org time):

1. Reads all active `Extole_Report_Config__c` records
2. For each config × each date range (Rolling 30, Rolling 90, YTD):
   - Constructs execution request per Execution Mapping rules
   - If Data Mode = Time Series: also executes prior period request for trend indicator
3. POSTs to `POST /v4/reports`
4. Polls for DONE status — interval and retry limit tuned by executor type:
   - SQL: short interval, few retries
   - CONFIGURED: moderate interval, moderate retries
   - SPARK: longer interval, higher retry limit
5. Downloads JSON output, locates `Value_Column`, applies `Aggregation`
6. If Time Series: extracts weekly data points into `Time_Series_JSON`, stores prior period value in `Prior_Period_Value`
7. Stores `view_url`, `report_id`, and `client_id` from the report response for tile click-through
8. Upserts `Extole_Report_Snapshot__c` (keyed on Config_Id + Date_Range)
9. Writes to `Extole_Sync_Log__c`
10. Reconciles orphaned snapshots by comparing active config set to existing snapshot records

Runs in integration user context. Uses `System.debug()` at key steps for SFDC native debug log compatibility.

**Polling risk note:** the sync job polls for report completion inside a scheduled Apex transaction. For slow SPARK reports this can hold the transaction open for several minutes. With 16 configs this is manageable in practice, but if a client configures many SPARK reports or report execution times increase, the job risks hitting Salesforce's transaction timeout. Mitigation: SPARK reports use conservative polling intervals and a higher retry limit per spec. If this becomes a production issue, the correct fix is a Queueable state machine — Job A triggers reports, Job B (scheduled 5 minutes later) checks status and downloads — which resets governor limits between jobs. Out of scope for v1 but the right architectural path if needed.

**On failure:** existing snapshot retained. Stale indicator shown. Error written to sync log.

**Raw output logging:** before any parsing or column extraction, the sync job must write the raw JSON response from `GET /v4/reports/{id}/download` to `Extole_Debug_Log__c` when debug logging is enabled. This is the single most important diagnostic tool for the first live integration — report output shape assumptions made during development will not always match production data.

**Sync batch ID:** every sync run generates a unique `Sync_Batch_Id` written to all `Extole_Sync_Log__c` and `Extole_Debug_Log__c` entries for that run. Makes it trivial to filter all log entries from a single sync cycle without scrolling through interleaved entries from different reports or runs.

---

## Extole API Endpoints Used

| Endpoint | Purpose |
|---|---|
| `GET /v6/report-types` | Populate report picker in Settings |
| `POST /v4/reports` | Trigger report execution |
| `GET /v4/reports/{id}` | Poll report status |
| `GET /v4/reports/{id}/download` | Download JSON report output |

Auth: `Authorization: Bearer <token>` via SFDC Named Credential. Single token per org.

---

## Permissions

Two Permission Sets ship with the package:

- `Extole_App_Viewer` — access to Program Overview and Lead Attribution tabs
- `Extole_App_Admin` — access to Settings tab, Named Credential configuration, metadata records

Named Credential access restricted to Apex integration context. Sync job runs in integration user context.

---

## Branding

The app uses SLDS for all UI components and respects the installing org's theme.

**Required branded elements:**
- Extole logo (SVG) in app header and onboarding screen. Stored as a static resource in the package.
- App nav icon uses Extole logo or a purpose-built derivative.
- Chart colors use Extole green (`#1D9E75`) as the primary data color across sparklines and bar charts.

---

## Admin Contextual Links

Direct links to relevant Extole pages at key decision points in the Settings tab.

| Location | Link text | Destination |
|---|---|---|
| Token entry | "Generate a token in My Extole →" | `my.extole.com/security-center` |
| Token entry | "How to generate a long-lived token →" | `dev.extole.com/docs/generate-long-lived-access-tokens` |
| Report picker header | "Manage reports in My Extole →" | `my.extole.com/reports` |
| Single report test result | "View full report in My Extole →" | `my.extole.com/reports` |
| Sync log error row | "Debug in Event Streams →" | `my.extole.com/tech-center/event-streams` |
| Onboarding Step 1 | "Where do I find my token? →" | `dev.extole.com/docs/generate-long-lived-access-tokens` |

All links open in a new tab. Link text uses sentence case with → suffix consistently.

---

## Onboarding & Install Experience

### First Launch State

Guided setup screen on first open — before token or config exists.

**Step 1: Connect to Extole**
- Prompt to enter API token with contextual links to My Extole Security Center and token docs
- "Test Connection" button — shows report count on success, specific error on failure
- Cannot proceed until connection confirmed

**Step 2: Configure Your First Report**
- Report picker opens automatically after successful connection
- Pre-filtered to Performance & Metrics category
- Inline guidance: "Select a report to add as a metric tile on your Program Overview tab"

**Step 3: Run First Sync**
- "Sync Now" triggered automatically after first report saved
- First sync runs in foreground with visible progress — not background
- On completion, navigates to Program Overview showing first tile
- Success state: "You're set up. Add more reports in Settings anytime."

### CSM Pre-requisites

Before handing the app to the client admin, the Extole CSM should:
1. Confirm appropriate reports are available via `GET /v6/report-types`
2. Generate a long-lived access token in the client's My Extole Security Center
3. Confirm RAF lead tagging is in place if Lead Attribution is desired
4. Note the `RAF_Tracking_Start_Date__c` value

A companion CSM onboarding guide should be maintained separately from this spec.

### Subsequent Installs / Reinstalls

App detects valid token and existing config on first launch and skips guided setup, going directly to Program Overview.

---

## Package Versioning & Upgrades

Config metadata, snapshot records, and Named Credentials are preserved across upgrades.

New fields are additive only — no existing fields removed or renamed in minor versions. Breaking changes require a major version increment with migration guidance.

Package version displayed in Settings tab footer for support purposes.

---

## Distribution

Distributed as an unlisted Salesforce managed package via direct install URL. No AppExchange listing.

**Install flow:**
1. Client requests app or CSM identifies it as a fit
2. CSM shares install URL and completes pre-requisite checklist
3. Client SFDC admin installs via URL
4. CSM walks admin through onboarding

**Version upgrades:** distributed via updated install URL. CSMs notify relevant clients. Upgrades are non-breaking.

**Support:** handled directly between Extole CS and client. Sync log and debug log are primary diagnostic tools.

---

## Debugging, Testing & Logging

### Sync Logging (Admin-visible)

`Extole_Sync_Log__c` — visible in Settings sync log table.

| Field | Type |
|---|---|
| Report_Name | Text |
| Date_Range | Text |
| Executor_Type | Text |
| Status | Picklist (SUCCESS, FAILED, SKIPPED) |
| Sync_Timestamp | DateTime (millisecond precision) |
| Value_Extracted | Text |
| HTTP_Status_Code | Number |
| Poll_Attempts | Number |
| Error_Message | Text |
| Sync_Batch_Id | Text |

### Debug Logging (Opt-in)

`Extole_Debug_Log__c` — off by default, enabled per report or globally in Settings. Captures full HTTP request/response, poll attempts, raw output excerpt, parsing errors, extracted value. Auto-purges after 7 days. "Clear Debug Logs" action in Settings.

| Field | Type |
|---|---|
| Report_Name | Text |
| Log_Timestamp | DateTime (millisecond precision) |
| Event_Type | Text |
| Detail | Long Text |
| Sync_Batch_Id | Text |

Captures:
- Full HTTP request body and response for every Extole API call
- Poll attempt number and status at each interval
- Exact Value Column name searched for alongside all columns present in the response — immediately surfaces column name mismatches
- Raw report output before parsing
- Extracted value before upsert, and upsert result separately

### Testing Tools (Settings Tab)

**Connection Test** — pings `GET /v6/report-types`, shows the first 3-5 report type names returned to confirm token scope is correct, not just that auth succeeded.

**Single Report Sync** — triggers one report from config detail panel. Shows live poll status with attempt count. Displays extracted value inline before committing to snapshot. Includes expandable raw output section so admin can see the full report response and verify column mapping without leaving SFDC.

**Config Validation** — on save: confirms `Value_Column` exists in `preview_columns`, warns on missing required parameters, warns if `formats` excludes JSON, blocks save if execution eligibility rules fail.

### SFDC-Native Debugging

`System.debug()` at key steps — API calls, poll intervals, value extraction, upsert operations. Compatible with standard SFDC Debug Logs.

---

## Tooltips

Tooltips appear on info icons next to config fields in the Settings tab. Two sources:

**Custom Labels (hardcoded, localizable):**

| Field | Tooltip text |
|---|---|
| Display Label | "What users see on the metric tile. Supports up to 120 characters. Defaults to the Extole report name." |
| Aggregation | "How to derive a single number from report output. Use FIRST_ROW for summary reports that return one row. Use SUM or COUNT for detail reports that return multiple rows." |
| Chart Type | "Sparkline shows a trend line over the selected period. Bar shows weekly volume. None shows the number only." |
| Date Range | "The time window for this metric. All three ranges are synced automatically to support the date toggle on the Overview tab." |
| Value Column | "The column from the report output to display as the metric value." + dynamic note (see below) |

**API-driven (dynamic):** Value Column tooltip appends the `note` field from `preview_columns` in the `ReportTypeResponse`. Surfaces Extole's own field descriptions inline without the admin leaving SFDC.

All tooltip text defined as Custom Labels for localization compliance.

---

## Localization

All UI strings defined as SFDC Custom Labels — no hardcoded strings in LWC templates or Apex. Date and number formatting handled automatically by SFDC locale. No translations bundled in v1. Architecture supports future translation via label files without code changes.

---

## Recommended Build Sequence

Build in phases — each is independently testable before moving to the next.

1. **Data model** — custom objects (`Extole_Report_Snapshot__c`, `Extole_Sync_Log__c`, `Extole_Debug_Log__c`), Custom Metadata Type (`Extole_Report_Config__mdt`), Named Credential setup
2. **Apex sync job** — background worker, polling logic tuned by executor type, snapshot upsert keyed on (Config_Id, Date_Range), orphan reconciliation, sync batch ID generation, debug logging
3. **Settings tab LWC** — connection section with test, report picker with default Performance & Metrics filter, two-step add report modal with column preview, sync management with log table
4. **Program Overview LWC** — tile grid, range toggle reading from pre-computed snapshots, sparkline and bar SVG rendering in JS, tile status variants, stale indicator, tile click-through
5. **Lead Attribution LWC** — SOQL query against Lead object, metric tiles, RAF vs. non-RAF comparison view, tracking since notice
6. **Onboarding flow** — first launch detection, three-step guided setup, foreground first sync with visible progress
7. **Packaging** — permission sets (`Extole_App_Viewer`, `Extole_App_Admin`), Custom Labels for all UI strings, Extole logo as static resource, app nav icon, install configuration, package version in Settings footer

---

## Addendum: LWC Developer Notes

Implementation guidance for the engineer building the LWC components. These are not spec decisions — they are recommended patterns based on SFDC/LWC constraints.

### Program Overview Tab

**Parent-child architecture.** The Overview tab should use a parent LWC that fetches all `Extole_Report_Snapshot__c` records for active configs in a single `@wire` or imperative Apex call. A child `extoleTile` LWC renders each tile. The parent holds `selectedRange` state and passes the filtered snapshot to each child via `@api`.

Use a getter to filter snapshots by range rather than re-fetching:
```js
get filteredSnapshots() {
  return this.snapshots.filter(s => s.Date_Range__c === this.selectedRange);
}
```

**SVG charts in JavaScript.** Generate `<path>` d-attributes and `<rect>` coordinates in JS and bind to the template. Do not use Chart.js or any third-party charting library — keeps the package lightweight and avoids LWC security sandbox issues.

**Range toggle.** No API call on toggle — just update `selectedRange` state variable and let the getter re-filter. Instant re-render from cached data.

**Responsive grid.** Use `lightning-layout` and `lightning-layout-item` with `size="12"`, `medium-device-size="6"`, `large-device-size="4"` to achieve the 1 → 2 → 3 column collapse.

**Orphaned tile opacity.** Bind CSS class dynamically:
```html
<div class={tileClass}>
```
```js
get tileClass() {
  return this.snapshot.Config_Status__c === 'ORPHANED' ? 'tile tile-orphaned' : 'tile';
}
```

**Stale indicator timezone.** `As_Of_Date__c` is stored in UTC. Convert to org timezone before computing stale threshold to avoid false positives. Use `Intl.DateTimeFormat` with the org's timezone offset.

**Extole green as CSS variable.** Define in component CSS:
```css
:host { --extole-green: #1D9E75; }
```
Reference via `var(--extole-green)` in SVG fills and strokes.

---

### Lead Attribution Tab

**Conditional rendering.** Use `lwc:if`:
```html
<template lwc:if={showLeadAttribution}>
```

**Empty states.** Use `lightning-illustration` for "no tagged leads yet" and error states to maintain native SFDC feel.

---

### Settings Tab

**Config panel as modal.** Use `lightning-modal` (or `lightning-overlay-container`) for the report detail / config panel. A modal provides focus and accommodates the depth of fields better than a side panel.

**MDT access via Apex.** LWCs cannot read Custom Metadata directly. Wrap all `Extole_Report_Config__mdt` reads and writes in `@AuraEnabled` Apex methods.

**Dynamic tooltip.** Combine Custom Label with API-sourced note in a getter:
```js
get valueColumnTooltip() {
  return `${this.labels.valueColumnBase} ${this.apiFieldNote || ''}`.trim();
}
```

**Connection test button.** Use `lightning-button` with a `isLoading` state bound to a spinner during the Named Credential callout. Prevents double-submit and signals activity immediately.

**Live report picker.** The picker calls `GET /v6/report-types` on open — wire this to an imperative Apex callout (not `@wire`) since it fires on user action, not on component load. Handle pagination with `limit=100&offset=N`.

---

### Debugging

**Log both sides of every API call.** Write the full HTTP request body alongside the response to `Extole_Debug_Log__c`. When a report execution fails it's often because the request was malformed — you need both sides to diagnose it.

**Log poll attempts individually.** Write attempt number and status at each polling interval. If a job times out you want to know whether it never started, ran for 9 minutes, or failed on attempt 2.

**Separate extracted value from upsert.** Log the extracted value before the upsert and the upsert result separately. Separates "got wrong data" from "got right data but failed to save it."

**Log column name mismatch explicitly.** When searching for `Value_Column` in report output, log the configured column name alongside all columns actually present in the response. The most common misconfiguration will be a column name that doesn't match what the report returns — this makes it instantly obvious without reading raw JSON.

**Use millisecond precision timestamps.** Async jobs running in parallel produce interleaved log entries that are impossible to read without precise timestamps. Use `System.now()` which includes milliseconds.

**Sync batch ID is mandatory.** Generate a unique ID at the start of each sync run and write it to every `Extole_Sync_Log__c` and `Extole_Debug_Log__c` entry produced by that run. Without this, filtering "everything from last night's sync" requires timestamp range queries across interleaved entries. With it, it's a single filter.

**Raw output before parsing.** Write the full raw JSON download response to debug log before any parsing. This is the most important single debugging aid for the first live integration — output shape assumptions will not always match production data.

**Single report test sync shows raw output.** The Settings tab test sync should include an expandable section showing the full raw report response. Admin should be able to verify column names and data without leaving SFDC.

---

### General

**All display numbers** must go through `Math.round()`, `.toFixed(n)`, or `Intl.NumberFormat` before rendering. JS float arithmetic leaks artifacts — never bind raw computed values directly to templates.

**Named Credential access** is restricted to server-side Apex — never expose the token or make callouts from client-side JS.

**Custom Labels** for all UI strings. No hardcoded text in templates or JS files. This applies to error messages, empty states, button labels, tooltip text, and status indicators.

---

## Open Questions

None.