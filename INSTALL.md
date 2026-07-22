# Extole SFDC App — Installation Guide

## Overview

Installation takes about 20–30 minutes and has two distinct phases.

**Phase 1 (Steps 1–3)** deploys the app and configures the Extole API connection. This covers Program Analytics and the KPI Dashboard — after Step 3 you can sync report data and see metrics in Salesforce.

**Phase 2 (Steps 4–6)** sets up the Tooling API OAuth connection required by the Event Configurator. Salesforce requires a Connected App and a one-time OAuth authorization to allow the app to generate and deploy Flows on your behalf. This is the most involved part of the setup but only needs to be done once per org.

Phase 2 is only needed for the Event Configurator — Program Analytics, the KPI Dashboard, and Share Link Backfill run entirely on the Step 3 credential. If you don't plan to use record-triggered events into Extole, skip Steps 4–6 and go straight to Step 7.

Steps 7–8 assign permissions and launch the app. Steps 9–11 cover optional features (Share Link Backfill, Receive Events, and the Person Card) — set up only the ones you plan to use.

Everything here is reversible: each feature is gated by its own permission set or toggle, so you can disable Event Configurator triggers, pause Receive Events, or remove permission set assignments at any time without side effects. Uninstalling the package entirely is a standard Salesforce package removal.

---

## Prerequisites

- **Git** with GitHub SSH access configured — [GitHub SSH setup docs](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- **Salesforce CLI** (`sf`) installed — [Install guide](https://developer.salesforce.com/tools/salesforcecli)
- **jq** installed (`brew install jq` on macOS)
- **python3** installed (standard on macOS)
- **Extole API token** — generate a long-lived token from the [Extole Security Center](https://my.extole.com/security-center) ([docs](https://dev.extole.com/docs/generate-long-lived-access-tokens))
- A Salesforce org on **Lightning Experience** with **API access enabled** (standard on all editions that support Connected Apps/External Client Apps)
- Installing user must be a Salesforce admin with:
    - Author Apex permission
    - Customize Application permission

---

## Step 1 — Clone the repository and authenticate

**In your terminal:**

```bash
git clone git@github.com:extole/extole-sfdc-app.git
cd extole-sfdc-app
```

Authenticate the Salesforce CLI to your org:

```bash
sf org login web --instance-url https://<your-org-domain>.my.salesforce.com --alias <alias>
```

Verify it worked:

```bash
sf org list
```

---

## Step 2 — Deploy the package

**In your terminal:**

```bash
sf project deploy start --target-org <alias>
```

Deploys all Apex classes, LWCs, custom objects, permission sets, and the Extole app.

---

## Step 3 — Configure the Extole API credential

**First, generate a long-lived API token in Extole:**

1. Log in to [my.extole.com](https://my.extole.com)
2. Go to **Security Center** → **Access Tokens** → **New Token**
3. Give it a descriptive name (e.g. `Salesforce Integration`) and set an appropriate expiry
4. Copy the token — you won't be able to see it again

**Then, in Salesforce Setup UI:**

5. Setup → Named Credentials → **External Credentials** tab
6. Click the **Extole API** name to open the full detail page (do not click Edit — that opens a modal)
7. Scroll to the **Custom Headers** section → find the `Authorization` row → click the dropdown arrow under **Actions** → **Edit**
8. Replace `REPLACE_WITH_BEARER_TOKEN` with: `Bearer <your_token>`
   _(include the word `Bearer` followed by a space)_
9. Save

---

## Step 4 — Create the External Client App

**In Salesforce Setup UI:**

The Extole app lets you configure which Salesforce record changes (e.g. a Lead being created, an Opportunity closing) trigger events sent to Extole. Under the hood, it creates Salesforce Flows to do this — and creating Flows programmatically requires an OAuth app connected to your org.

1. Setup → **External Client App Manager** → click the **New External Client App** button
2. Under **Basic Information**, fill in:
    - **App Name:** `Extole Deployer`
    - **API Name:** `Extole_Deployer`
    - **Contact Email:** your admin email address
    - **Logo Image URL:** `https://www.extole.com/wp-content/uploads/2023/07/Extole-icon-bug.svg`
    - **Distribution:** Local
3. Check **Enable OAuth Settings**
4. Under **OAuth Settings**, configure:
    - **Callback URL:** `https://login.salesforce.com/services/oauth2/callback`
      _(placeholder — you will replace this after the Auth Provider deploys in Step 5)_
    - **OAuth Scopes** — add both:
        - **Manage user data via APIs (api)**
        - **Perform requests at any time (refresh_token, offline_access)**
5. Under **Flow Enablement**, check:
    - **Enable Authorization Code and Credentials Flow**
    - Leave **Require user credentials in the POST body for Authorization Code and Credentials Flow** unchecked
6. Under **Security**, uncheck:
    - **Require Proof Key for Code Exchange (PKCE) extension for Supported Authorization Flows**
7. Click **Create** — the app is enabled immediately

---

## Step 5 — Run the Tooling credential setup script

**In your terminal:**

```bash
bash scripts/setup_named_credential.sh --target-org <alias>
```

The script deploys the Auth Provider and Named Credential, and pauses at points where Salesforce requires manual UI steps. Follow the prompts exactly.

**The script will walk you through:**

**a. Find the Consumer Key and Secret**

> In Salesforce Setup UI:
> Setup → **External Client App Manager** → click **Extole Deployer** → **Settings** tab → **OAuth Settings** → **Consumer Key and Secret**

**b. Update the callback URL** _(after the Auth Provider deploys)_

> In Salesforce Setup UI:
>
> 1. Setup → **Auth Providers** → **Extole Tooling Auth** → copy the **Callback URL** shown on the detail page
>    _(looks like `https://<your-org>.my.salesforce.com/services/authcallback/Extole_Tooling_Auth`)_
> 2. Setup → **External Client App Manager** → **Extole Deployer** → **Settings** tab → **Edit** → scroll to the **OAuth Settings** section → replace the Callback URL with the value you just copied → **Save**

**c. Create the External Credential** _(after updating the callback URL)_

> In Salesforce Setup UI:
>
> Setup → **Named Credentials** → **External Credentials** tab → **New**:
>
> - **Label:** `Extole Tooling Cred`
> - **Name:** `Extole_Tooling_Cred`
> - **Authentication Protocol:** OAuth 2.0
> - **Authentication Flow Type:** Browser Flow — _this reveals an Identity Provider field_
> - **Identity Provider:** change the dropdown to **Auth Provider**, then select `Extole Tooling Auth`
> - **Scope:** leave blank
>
> Save.
>
> Then on the detail page of the **Extole Tooling Cred** you just created, under **Principals** → **New**:
>
> - **Parameter Name:** `Admin`
> - **Identity Type:** Named Principal
> - **Scope:** leave blank
>
> Save, then return to the terminal and press ENTER.

---

## Step 6 — Authorize the Tooling credential (one-time OAuth)

**In Salesforce Setup UI:**

1. Setup → **Named Credentials** → **External Credentials** tab
2. Click **Extole Tooling Cred**
3. Under **Principals**, click **Authenticate** next to the Admin principal
4. Log in with the admin account (must have Author Apex + Customize Application)
5. Approve the OAuth consent screen

> The orange "Security Warning" block on the consent screen is standard Salesforce behavior for all Connected Apps and is not specific to this app.

This is a one-time step. After authorization, the Event Configurator can deploy Flows without requiring a browser session.

> The setup script automatically grants the `Extole_App_Admin` permission set access to the Tooling credential.

---

## Step 7 — Assign permission sets

**In your terminal:**

Assign `Extole_App_Admin` to yourself and any other admins who will configure Program Analytics, the KPI Dashboard, or the events sent to Extole:

```bash
sf org assign permset --name Extole_App_Admin --target-org <alias>
```

Assign `Extole_App_Viewer` to any user who needs read access to Program Analytics, the KPI Dashboard, and List View:

```bash
sf org assign permset --name Extole_App_Viewer --target-org <alias>
```

To assign to another user, add `--on-behalf-of <username>` to either command.

> **Recommended for production orgs:** Create a dedicated Integration User (a non-human Salesforce user with a full license) and assign it `Extole_App_Admin`. Perform the Tooling API OAuth authorization in Step 6 while logged in as that user. This ensures the Event Configurator remains functional even if the original admin's account is deactivated or their session expires.

Both permission sets grant visibility into the **Extole** app itself, so assigning either one is sufficient to make it appear in the App Launcher — no separate App Manager step is needed. (See Troubleshooting below if the app still doesn't appear for a user.)

---

## Step 8 — Launch and complete onboarding

1. Open the **Extole** app from the App Launcher (grid icon, top left)
2. The Getting Started screen will appear on first launch
3. Open the **Configure Events** tab → click **Test Connection** — verify it shows "Connected"
4. Open the **Configure KPIs** tab → click **Add Report** and configure your first KPI
    - Reports must already exist and be scheduled in the Extole platform — if a report hasn't run yet, the sync will return no data
5. Trigger a manual sync from the Configure KPIs tab — your KPI Dashboard will populate once the first sync completes

> **If you have the Extole CLI:** run `extole events stream` and then trigger a Salesforce record change (e.g. create a Lead). You should see the event arrive in Extole in real time.

---

## Step 9 — Set up Share Link Backfill _(optional)_

The **Manage Share Links** tab generates Extole share links for existing Contacts or Leads and writes them to a custom field on each record. The custom field (`Extole_Share_Link__c`, type URL) is deployed with the package automatically — but it must be manually added to your page layouts to be visible on individual records.

**Add the field to the Contact page layout:**

1. Setup → **Object Manager** → **Contact** → **Page Layouts**
2. Open the layout in use (typically `Contact Layout`)
3. In the field palette, find **Extole Share Link** (under URL fields, or search by name)
4. Drag it onto the layout in the desired section
5. Save

**Add the field to the Lead page layout:**

1. Setup → **Object Manager** → **Lead** → **Page Layouts**
2. Open the layout in use (typically `Lead Layout`)
3. Find **Extole Share Link** and drag it onto the layout
4. Save

**Run a backfill:**

1. Open the **Manage Share Links** tab
2. Choose an audience: **Closed/Won opps** (Contacts on accounts with Closed Won opportunities), **Date range** (records created in a window), or **Custom report** (any Salesforce report you've built)
3. Choose the program/campaign from Extole — share links are scoped to a campaign
4. Click **Start Backfill**
5. Monitor progress in the backfill log on the same tab — each record's outcome (success / error / skipped) is recorded

> The backfill is idempotent — re-running for the same person fetches their existing share link rather than creating a duplicate.

---

## Step 10 — Set up Receive Events (optional)

The **Receive Events** tab lets Extole send events (e.g. a reward being earned) into Salesforce, where they get written to a matching Contact or Lead. This direction is the reverse of everything above — Extole calls into Salesforce, so the auth setup lives on the Salesforce side, in the form of a Connected App, plus a matching credential stored in Extole's own Security Center.

**In Salesforce Setup UI:**

1. Setup → **App Manager** → **New Connected App**
2. Enable **OAuth Settings**, then add these two scopes:
    - **Perform requests at any time (refresh_token, offline_access)**
    - **Access and manage your data (api)**
3. Under **OAuth Settings**, check **Enable Client Credentials Flow**
4. Save, then open the app's detail page to find the **Consumer Key** and **Consumer Secret**

**In the Receive Events tab:**

5. Copy the **Webhook Endpoint** URL shown at the top of the tab (`.../services/apexrest/extole/events`) — this is generated dynamically from your org's own domain (`ExtoleWritebackController.getEndpointUrl()`), so it's always correct for whichever org you view it in

**In Extole (my.extole.com → Security Center):**

6. Create a new key with:
    - **Key Name** — something identifiable, e.g. "Salesforce Client Credentials"
    - **Algorithm** — **`OAUTH_SFDC`** (not `OAUTH_SALESFORCE` or `OAUTH_SFDC_PASSWORD` — those are for different auth patterns; `OAUTH_SFDC` is specifically built for Salesforce's Client Credentials flow, since Salesforce's token response omits `expires_in`, which the generic `OAUTH` algorithm requires)
    - **Key** — the Connected App's **Consumer Secret**
    - **Authorization URL** — `https://<your-org-domain>.my.salesforce.com/services/oauth2/token`
    - **OAuth Client ID** — the Connected App's **Consumer Key**

**Back in the Extole component's configuration:**

7. Set the Security Center key from step 6 as the `CLIENT_KEY` setting, and the endpoint URL from step 5 as the webhook target setting
8. Check the **Enable Salesforce Writeback** setting to turn on the outbound webhooks. This is **off by default** — if your account doesn't want any data written back to Salesforce, simply leave it unchecked. No request is ever built or sent while off (checked at the very start of the webhook's own script, before any reward/event data is touched), so nothing leaves the Extole platform and nothing is logged on either side — this is different from just arriving and being silently skipped.

> Keep the endpoint URL and client key filled in even during testing or if you want to pause writeback for a while — use the **Enable Salesforce Writeback** toggle for that instead. Extole treats these two fields as required once the integration is active, so clearing them blocks saving further changes until they're restored. 9. Click **Add Rule** under **Writeback Rules** to map incoming event fields to Contact or Lead fields — target fields must be **Text** type; `ExtoleWebhookController.applyMappings()` always writes values as strings, so a Number/Date field will silently fail to populate 10. Trigger a test event from Extole and confirm it appears in the **Event Log** on the same tab

> Requires `Extole_App_Admin` — the underlying `ExtoleWebhookController`/`ExtoleWritebackController` classes and the `Extole_Writeback_Cfg__c`/`Extole_Writeback_Log__c` objects are only accessible to that permission set.

**Sending non-reward events:** rewards flow to Salesforce automatically once writeback is on. To send other business events (a share, a referral click, a custom action), add a **Webhook** step to that event's flow in Extole and point it at the GENERIC writeback webhook. Since the webhook simply forwards whatever data is present on that step, include a `data` field on the step with the values you want written to Salesforce, for example:

```
javascript@runtime:(function () {
    var person = context.getGlobalServices().getPersonService()
        .lookupPerson().withPersonId(context.getPerson().getId()).lookup();
    return {
        email: person ? person.getEmail() : null,
        salesforce_id: (person && person.data) ? person.data['salesforce_id'] : null
    };
})();
```

Save that change in Extole, trigger a test event, and confirm it appears in the Receive Events **Event Log** here in Salesforce.

---

## Step 11 — Add the Person Card to Lead/Contact pages (optional)

The Person Card is a Lightning component that surfaces a person's Extole share links, referred friends (with per-friend journey progress), and referrer attribution. It reflects the referral relationship structure specifically — rewards earned outside a referral (e.g. a standalone reward-for-action program) won't appear on it.

Dropping it directly into an existing sidebar/column tends to make the Details view feel cluttered, especially alongside other packages' widgets. The recommended pattern instead — matching how packages like ChurnZero add their own record-detail tab — is to give it its own tab:

1. Open a **Lead** or **Contact** record → click the gear icon → **Edit Page**
2. Add a new tab to the record page's tab set (name it whatever fits your org, e.g. "Refer-a-Friend")
3. Drag the **Extole Person Card** component into that new tab's content area
4. Save, then **Activate** the page for the org/profiles that need it (if not already activated)
5. Repeat for the other object (Lead and Contact are configured independently)

The component exposes a **Disabled** checkbox in the page's properties panel (click the component in App Builder to see it) — check it to turn the card off without removing it from the page.

---

## Troubleshooting

| Symptom                                                                                                                                                  | Likely cause                                                                                                                                                                                                                                                                                                                                                                                     |
| -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `InvalidProjectWorkspaceError` on deploy                                                                                                                 | You are not inside the cloned repo directory. Run `cd extole-sfdc-app` first.                                                                                                                                                                                                                                                                                                                    |
| "Test Connection" fails                                                                                                                                  | Bearer token wrong, missing, or expired. Re-check Step 3.                                                                                                                                                                                                                                                                                                                                        |
| Event Configurator deploy fails                                                                                                                          | Tooling OAuth not completed. Re-check Step 6.                                                                                                                                                                                                                                                                                                                                                    |
| Scheduled sync not running                                                                                                                               | Go to **Configure KPIs**, change Sync Cadence and save to re-register the job.                                                                                                                                                                                                                                                                                                                   |
| Permission errors on objects                                                                                                                             | User missing `Extole_App_Admin` or `Extole_App_Viewer` permission set.                                                                                                                                                                                                                                                                                                                           |
| Share Link field not visible on Contact/Lead                                                                                                             | Field is deployed but not on the page layout — see Step 9.                                                                                                                                                                                                                                                                                                                                       |
| Extole app doesn't appear in App Launcher for a user                                                                                                     | Confirm they're assigned `Extole_App_Admin` or `Extole_App_Viewer` (Setup → Permission Sets → the set → Manage Assignments). If assigned and still missing, redeploy the permission set — its `applicationVisibilities` grant may not have deployed.                                                                                                                                             |
| "You do not have access to the Apex class named '...'" error on any tab                                                                                  | The user's assigned permission set doesn't grant that class. Check Setup → Permission Sets → the set → Apex Class Access.                                                                                                                                                                                                                                                                        |
| A tab renders but shows no data (e.g. "No live Extole programs found") with no explicit error                                                            | The LWC may be silently swallowing a permission exception rather than surfacing it. Check the user's actual Apex debug log (Setup → Debug Logs, add a trace flag on their user) for the real error before assuming it's a data issue — this exact symptom was caused by a missing **read** permission on the standard `UserExternalCredential` object, not by the Extole API or the data itself. |
| Receive Events shows no incoming events                                                                                                                  | Confirm the Connected App's Client Credentials flow is enabled and its Consumer Key/Secret match the Extole component's `CLIENT_KEY` setting (see Step 10). Check the Event Log on the tab for delivery attempts and errors.                                                                                                                                                                     |
| Extole webhook dispatch returns `401 INVALID_SESSION_ID`, even though the Connected App's token exchange succeeds when tested directly (e.g. via `curl`) | The webhook's request script is likely built from `context.createRequestBuilder()` instead of `context.createRequestBuilderWithDefaults()` — only the latter attaches the `CLIENT_KEY`'s Authorization header. This produces a request that looks correct in every other way (right URL, right body) but is silently unauthenticated.                                                            |

For detailed diagnostics, enable **Debug Logging** on the **Configure Events** tab and check the KPI Data Import Log on the **Configure KPIs** tab.
