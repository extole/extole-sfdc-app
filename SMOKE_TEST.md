# Extole SFDC App — Smoke Test Script

## Prerequisites

- Deployed to `extole-sandbox` (or target org)
- Named Credential `Extole_API` configured with valid Bearer token
- `Extole_App_Admin` permission set assigned to test user
- At least one `Extole_Report_Config__c` record exists (ACQUISITION_RATE recommended)

---

## 1. Onboarding Flow

**Steps:**
1. Open the Extole App tab in Salesforce
2. If no settings exist, the 3-step onboarding modal should appear automatically
3. Step 1: Enter a valid API token → click Next
4. Step 2: Review detected report types → click Next
5. Step 3: Confirm setup summary → click Finish

**Pass criteria:**
- Modal progresses through all 3 steps without error
- Settings tab shows the entered token saved
- App loads the main Program Overview after finishing

---

## 2. Connection Test

**Steps:**
1. Go to Settings tab → API Connection section
2. Click **Test Connection**

**Pass criteria:**
- Badge shows "Connected" in green
- Result message shows report count (e.g., "Found 12 report runners")

**Failure path test:**
1. Temporarily enter an invalid token → Save Settings → Test Connection
2. Badge should show "Failed" in red with an error message
3. Re-enter valid token → Save Settings → Test Connection → should pass again

---

## 3. Settings Save & Persistence

**Steps:**
1. Go to Settings tab
2. Change **Sync Cadence** to a different value
3. Change **Notify On Sync Failure** checkbox
4. Change **Notify After N Failures** to 1
5. Click **Save Settings**
6. Hard reload the page (Ctrl+Shift+R / Cmd+Shift+R)
7. Return to Settings tab

**Pass criteria:**
- All changed values persist after reload
- No fields reset to defaults

---

## 4. Unsaved Settings Warning

**Steps:**
1. Go to Settings tab
2. Change any setting (do NOT save)
3. Observe the sync action row — an "Unsaved changes" warning badge should appear
4. Click **Sync Now** without saving

**Pass criteria:**
- Warning toast appears: "You have unsaved settings changes. Save your settings before syncing..."
- Sync does NOT proceed
- After clicking **Save Settings**, the badge disappears
- **Sync Now** proceeds normally after save

---

## 5. Manual Sync

**Steps:**
1. Go to Settings tab → Sync Management section
2. Click **Sync Now**

**Pass criteria:**
- Button shows spinner while syncing
- Sync Log table updates with a new row
- New row shows: report name, date range, status (SUCCESS or FAILED), timestamp, HTTP status, value extracted
- "Last Sync:" label updates to the current time (e.g., "Mar 26, 2:14 PM") — NOT "Never"

---

## 6. Sync Log — Failed Sync

**Steps:**
1. Temporarily clear/invalidate the API token in the Named Credential
2. Click **Sync Now**
3. Observe the new Sync Log row

**Pass criteria:**
- Status column shows FAILED (red)
- HTTP Status column shows `403` (not blank)
- Error Message column shows a truncated error; hovering shows full text via tooltip

---

## 7. Sync Log — Timestamp Format

**Pass criteria:**
- Sync Log timestamps display in human-readable format: e.g., `Mar 26, 2:14 PM`
- NOT raw ISO format like `2026-03-26T14:14:00.000Z`

---

## 8. Program Overview — Tile Rendering

**Steps:**
1. Go to Program Overview tab
2. Select a date range (e.g., Rolling 30)

**Pass criteria:**
- At least one metric tile renders with a value
- Tile shows label, value, and (if time series data exists) a sparkline or bar chart
- Prior period comparison badge shows (up/down arrow with %)

---

## 9. Debug Logging Toggle

**Steps:**
1. Go to Settings tab → Debug section
2. Enable **Debug Logging** → Save Settings
3. Click **Sync Now**
4. Scroll to the Debug Logs table in the Debug section

**Pass criteria:**
- Debug log entries appear with event types like `HTTP_REQUEST`, `HTTP_RESPONSE`, `VALUE_EXTRACTED`
- Timestamp column is wide enough to show full date (e.g., `Mar 26, 2:14 PM`)
- Detail column is not red — neutral color
- Hovering over truncated detail shows full text via tooltip
- Batch ID column is narrow (truncated with tooltip if long)

**Off test:**
1. Disable **Debug Logging** → Save Settings
2. Click **Sync Now**
3. Check Debug Logs — no new entries should appear (count stays the same)

**Clear test:**
1. Click **Clear Debug Logs**
2. Debug log table should show empty state ("No debug logs recorded.")

---

## 10. Report Config — Add / Edit / Delete

**Steps:**
1. Go to Settings tab → Report Configurations section
2. Click **Add Report** — the add modal should open
3. Step 1: Select a report type from the list → Next
4. Step 2: Configure label, value column, aggregation, chart type → Next
5. Step 3: Review → Save
6. New config appears in the config list

**Edit:**
1. Click the row action (pencil/edit) on an existing config
2. Change the Display Label
3. Save → label updates in the list

**Delete:**
1. Click delete on a config
2. Confirm in the dialog
3. Config is removed from the list; corresponding snapshot is orphaned (Config_Status = ORPHANED)

---

## 11. Clear Orphaned Snapshots

**Steps:**
1. Delete a Report Config (creates an orphaned snapshot per test 10)
2. Go to Settings tab → Maintenance section
3. Click **Clear Orphaned Snapshots**

**Pass criteria:**
- Toast confirms N snapshots deleted
- Orphaned snapshot no longer appears in Program Overview

---

## 12. Scheduled Sync (Cadence)

**Steps:**
1. Set Sync Cadence to `Hourly` → Save Settings
2. Verify a scheduled job exists: Setup → Apex Jobs → Scheduled Jobs → look for `ExtoleSyncJob`
3. Set Sync Cadence to `None` → Save Settings
4. Verify the scheduled job is removed

**Pass criteria:**
- Job appears when cadence is set
- Job is removed when cadence is set to None

---

## 13. Failure Notification Email

**Steps:**
1. Set **Notify On Sync Failure** = enabled, **Notify After N Failures** = 1, enter a valid email → Save Settings
2. Invalidate the API token
3. Click **Sync Now**

**Pass criteria:**
- Sync fails with FAILED status in sync log
- Debug log shows `EMAIL_SENT` event with "Failure notification sent to: [email]"
- Email is received in inbox

---

## 14. Lead Attribution Tab

**Steps:**
1. Go to Lead Attribution tab
2. If RAF settings are configured, the tab should show lead attribution data

**Pass criteria:**
- Tab loads without error
- Empty state is shown if no RAF configuration is set up (graceful, not a crash)

---

## Pass/Fail Summary

| # | Test | Result | Notes |
|---|------|--------|-------|
| 1 | Onboarding Flow | | |
| 2 | Connection Test | | |
| 3 | Settings Save & Persistence | | |
| 4 | Unsaved Settings Warning | | |
| 5 | Manual Sync | | |
| 6 | Failed Sync — HTTP Status | | |
| 7 | Sync Log Timestamp Format | | |
| 8 | Program Overview Tiles | | |
| 9 | Debug Logging Toggle | | |
| 10 | Report Config Add/Edit/Delete | | |
| 11 | Clear Orphaned Snapshots | | |
| 12 | Scheduled Sync Cadence | | |
| 13 | Failure Notification Email | | |
| 14 | Lead Attribution Tab | | |
