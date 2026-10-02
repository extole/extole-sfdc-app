# Extole SFDC App — Installation Guide

## Overview

Installation takes about 20–30 minutes and has two distinct phases.

**Phase 1 (Steps 1–3)** deploys the app and configures the Extole API connection. This covers Program Analytics and the KPI Dashboard — after Step 3 you can sync report data and see metrics in Salesforce.

**Phase 2 (Steps 4–6)** sets up the Tooling API OAuth connection required by the Event Configurator. Salesforce requires a Connected App and a one-time OAuth authorization to allow the app to generate and deploy Flows on your behalf. This is the most involved part of the setup but only needs to be done once per org.

Phase 2 is only needed for the Event Configurator — Program Analytics, the KPI Dashboard, and Share Link Backfill run entirely on the Step 3 credential. If you don't plan to use record-triggered events into Extole, skip Steps 4–6 and go straight to Step 7.

Steps 7–8 assign permissions and launch the app. Steps 9–11 cover optional features (Share Link Backfill, Receive Extole Events, and the Person Card) — set up only the ones you plan to use.

Everything here is reversible: each feature is gated by its own permission set or toggle, so you can disable Event Configurator triggers, pause Receive Extole Events, or remove permission set assignments at any time without side effects. Uninstalling the package entirely is a standard Salesforce package removal.

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

This app authenticates to the Tooling API using the OAuth 2.0 **JWT Bearer Flow** rather than the interactive Authorization Code ("Browser") flow. Salesforce now requires PKCE on Authorization Code flows for External Client Apps, and in many orgs that requirement can no longer be turned off — but PKCE only applies to the Authorization Code flow family. JWT Bearer Flow doesn't use an authorization code at all, so it isn't subject to that requirement, and as a bonus it doesn't need a one-time interactive "Authenticate" click either.

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
     _(placeholder — this flow never redirects, but the field is required)_
   - **OAuth Scopes** — add both:
     - **Manage user data via APIs (api)**
     - **Perform requests at any time (refresh_token, offline_access)**
5. Under **Flow Enablement**, check:
   - **Enable JWT Bearer Flow**
   - Leave **Enable Authorization Code and Credentials Flow** unchecked — it isn't needed for this credential and is exactly the flow type that triggers the PKCE requirement
6. Click **Create** — the app is enabled immediately
7. Open the app's row action → **Edit Policies** → under **OAuth Policies**, set **Permitted Users**
   to **Admin approved users are pre-authorized**, then under **App Policies** move
   `Extole App Admin` into **Selected Permission Sets** → Save. JWT Bearer Flow has no interactive
   consent step, so without this the token exchange fails with
   `invalid_grant: user hasn't approved this consumer` even though the certificate, External
   Credential, and Named Credential are all configured correctly — the default **Permitted Users**
   value ("All users may self-authorize") assumes a user can click through a consent screen, which
   never happens under this flow.

You'll come back to this app in Step 5 to upload a signing certificate.

---

## Step 5 — Run the Tooling credential setup script

**In your terminal:**

```bash
bash scripts/setup_named_credential.sh --target-org <alias>
```

The script deploys the Named Credential, and pauses at points where Salesforce requires manual UI steps (certificate creation and the External Client App's/External Credential's secret-bearing fields aren't scriptable via Metadata API). Follow the prompts exactly.

**The script will walk you through:**

**a. Create a signing certificate**

> In Salesforce Setup UI:
>
> Setup → **Certificate and Key Management** → **Create Self-Signed Certificate**:
> - **Label:** `Extole Tooling JWT Cert`
> - **Unique Name:** `Extole_Tooling_JWT_Cert`
> - Leave Key Size and Exportable Private Key at their defaults
>
> Save, then click **Download Certificate** and note where the `.crt` file was saved — you'll upload it in the next step.

**b. Enable JWT Bearer Flow on the External Client App**

> In Salesforce Setup UI:
>
> Setup → **External Client App Manager** → **Extole Deployer** → row action → **Edit Settings** → expand **OAuth Settings** → scroll to **Flow Enablement** (you already checked **Enable JWT Bearer Flow** in Step 4):
> - Under **Certificate Upload**, click **Upload Files** and select the `.crt` file you downloaded in step (a)
>
> Save.

**c. Find the Consumer Key**

> In Salesforce Setup UI:
> Setup → **External Client App Manager** → **Extole Deployer** → **Settings** tab → **OAuth Settings** → **Consumer Key and Secret** → copy the **Consumer Key** (you don't need the secret for this flow)

**d. Create the External Credential**

> In Salesforce Setup UI:
>
> Setup → **Named Credentials** → **External Credentials** tab → **New**:
>
> - **Label:** `Extole Tooling Cred`
> - **Name:** `Extole_Tooling_Cred`
> - **Authentication Protocol:** OAuth 2.0
> - **Authentication Flow Type:** JWT Bearer Flow — _this reveals Common Claims and JWT Signing fields_
> - **Identity Provider URL:** `https://<your-org-domain>/services/oauth2/token`
> - **Issuer (iss):** the Consumer Key you copied in step (c)
> - **Subject (sub):** the username of the admin who will run the Event Configurator (e.g. a dedicated Integration User — see the note in Step 7)
> - **Audience (aud):** `https://<your-org-domain>` (no path)
> - **Signing Certificate:** `Extole Tooling JWT Cert` (the certificate from step (a))
> - **Signing Algorithm:** RS256 (default)
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

## Step 6 — Verify the Tooling credential

Unlike the Authorization Code flow, JWT Bearer Flow needs no interactive consent step — there's no "Authenticate" button to click. The Named Credential is ready to use as soon as it's deployed.

**In Salesforce Setup UI:**

1. Setup → **Named Credentials** → **Named Credentials** tab → click **Extole Tooling**
2. Confirm the page shows no errors

The real test happens in Step 8: opening the app and clicking **Test Connection** / creating an Event Configuration will exercise this credential end-to-end.

> The setup script automatically grants the `Extole_App_Admin` permission set access to the Tooling credential.

> **If a deploy or event fires and fails with an auth error:** unlike Browser Flow, there's no "click Authenticate to re-authorize" fix. Check instead that the certificate in Certificate and Key Management hasn't expired or been deleted, and that the Issuer/Subject/Audience values on the External Credential still match the External Client App's Consumer Key and your org's domain — these are the three fields Salesforce doesn't auto-populate for this flow.

---

## Step 7 — Assign permission sets

**In your terminal:**

Assign `Extole_App_Admin` to yourself and any other admins who will configure Program Analytics, the KPI Dashboard, or the events sent to Extole:

```bash
sf org assign permset --name Extole_App_Admin --target-org <alias>
```

Assign `Extole_App_Viewer` to any user who needs read access to Program Analytics and the KPI Dashboard:

```bash
sf org assign permset --name Extole_App_Viewer --target-org <alias>
```

To assign to another user, add `--on-behalf-of <username>` to either command.

> **Recommended for production orgs:** Create a dedicated Integration User (a non-human Salesforce user with a full license), assign it `Extole_App_Admin`, and use its username as the **Subject (sub)** value on the `Extole Tooling Cred` External Credential (Step 5d) instead of a personal admin account. This ensures the Event Configurator remains functional even if the original admin's account is deactivated.

Both permission sets grant visibility into the **Extole** app itself, so assigning either one is sufficient to make it appear in the App Launcher — no separate App Manager step is needed. (See Troubleshooting below if the app still doesn't appear for a user.)

---

## Step 8 — Launch and complete onboarding

1. Open the **Extole** app from the App Launcher (grid icon, top left)
2. The Getting Started screen will appear on first launch
3. Open the **Send Extole Events** tab → click **Test Connection** — verify it shows "Connected"
4. Open the **Configure KPIs** tab → click **Add KPI** and configure your first KPI
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

## Step 10 — Set up Receive Extole Events (optional)

The **Receive Extole Events** tab lets Extole send events (e.g. a reward being earned) into Salesforce, where they get written to a matching Contact or Lead. This direction is the reverse of everything above — Extole calls into Salesforce, so the auth setup lives on the Salesforce side, in the form of an External Client App using the Client Credentials flow, plus a matching credential stored in Extole's own Security Center.

**In Salesforce Setup UI:**

1. Setup → **External Client App Manager** → click the **New External Client App** button
2. Under **Basic Information**, fill in an **App Name** (e.g. `Extole Receive Events`), matching **API Name**, a **Contact Email**, and set **Distribution** to Local
3. Check **Enable OAuth Settings**, then under **OAuth Settings** add these two scopes:
    - **Perform requests at any time (refresh_token, offline_access)**
    - **Manage user data via APIs (api)**
4. Under **Flow Enablement**, check **Enable Client Credentials Flow**
5. Click **Create**
6. Open the app's row action → **Edit Policies** → under **OAuth Policies**:
    - Set **Permitted Users** to **Admin approved users are pre-authorized** — Client Credentials Flow has no interactive consent step, so without this the token exchange fails with `invalid_grant: user hasn't approved this consumer` even though every other setting is correct
    - Under **Client Credentials Flow**, set the **Run As** user to a dedicated integration user (or an admin) — this is the Salesforce identity every inbound Extole event will execute as
    - Save
7. Back on the app's **Settings** tab, under **OAuth Settings**, find the **Consumer Key** and **Consumer Secret**

**In the Receive Extole Events tab:**

8. Copy the **Webhook Endpoint** URL shown at the top of the tab (`.../services/apexrest/extole/events`) — this is generated dynamically from your org's own domain (`ExtoleWritebackController.getEndpointUrl()`), so it's always correct for whichever org you view it in

**In Extole (my.extole.com → Security Center):**

9. Create a new key with:
    - **Key Name** — something identifiable, e.g. "Salesforce Client Credentials"
    - **Key Type** — **Webhook**
    - **Algorithm** — **`OAUTH_SFDC`** (not `OAUTH_SALESFORCE` or `OAUTH_SFDC_PASSWORD` — those are for different auth patterns; `OAUTH_SFDC` is specifically built for Salesforce's Client Credentials flow, since Salesforce's token response omits `expires_in`, which the generic `OAUTH` algorithm requires)
    - **Key** — the External Client App's **Consumer Secret**
    - **Authorization URL** — `https://<your-org-domain>.my.salesforce.com/services/oauth2/token`
    - **OAuth Client ID** — the External Client App's **Consumer Key**

**Back in the Extole component's configuration:**

> Steps 10-11 assume the Extole-side "Salesforce" integration component already exists for your
> account. If it doesn't yet, it isn't something this app deploys — it lives in
> [extole-sfdc-component](https://github.com/extole/extole-sfdc-component), which has its own
> README covering what it is and how to install it (there's no deploy script yet, so it's a manual
> Management API build).

10. Set the Security Center key from step 9 as the `CLIENT_KEY` setting, and the endpoint URL from step 8 as the webhook target setting
11. Check the **Enable Salesforce Writeback** setting to turn on the outbound webhooks. This is **off by default** — if your account doesn't want any data written back to Salesforce, simply leave it unchecked. No request is ever built or sent while off (checked at the very start of the webhook's own script, before any reward/event data is touched), so nothing leaves the Extole platform and nothing is logged on either side — this is different from just arriving and being silently skipped.

> Keep the endpoint URL and client key filled in even during testing or if you want to pause writeback for a while — use the **Enable Salesforce Writeback** toggle for that instead. Extole treats these two fields as required once the integration is active, so clearing them blocks saving further changes until they're restored.

12. Click **Add Rule** under **Rules** to map incoming event fields to Contact or Lead fields — target fields must be **Text** type; `ExtoleWebhookController.applyMappings()` always writes values as strings, so a Number/Date field will silently fail to populate
13. Trigger a test event from Extole and confirm it appears in the **Event Log** on the same tab

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

Save that change in Extole, trigger a test event, and confirm it appears in the Receive Extole Events **Event Log** here in Salesforce.

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
| Event Configurator deploy fails with "named credential ... might not exist"                                                                              | The Named Credential must be named exactly `Extole_Tooling` (label "Extole Tooling") — re-check Step 5d/the script output.                                                                                                                                                                                                                                                                       |
| Event Configurator deploy fails with a JWT/token exchange error                                                                                          | Re-check Step 5: the signing certificate hasn't expired or been deleted from Certificate and Key Management, and the External Credential's Issuer/Subject/Audience still match the External Client App's Consumer Key and your org's domain.                                                                                                                                                    |
| Token exchange fails with `invalid_grant: user hasn't approved this consumer`, even though the certificate/credential/domain all check out                | Re-check Step 4.7: the External Client App's **Permitted Users** OAuth Policy must be **Admin approved users are pre-authorized**, with `Extole App Admin` in Selected Permission Sets. The default **All users may self-authorize** requires an interactive consent click that JWT Bearer Flow never triggers.                                                                                 |
| Scheduled sync not running                                                                                                                               | Go to **Configure KPIs**, change Sync Cadence and save to re-register the job.                                                                                                                                                                                                                                                                                                                   |
| Permission errors on objects                                                                                                                             | User missing `Extole_App_Admin` or `Extole_App_Viewer` permission set.                                                                                                                                                                                                                                                                                                                           |
| Share Link field not visible on Contact/Lead                                                                                                             | Field is deployed but not on the page layout — see Step 9.                                                                                                                                                                                                                                                                                                                                       |
| Extole app doesn't appear in App Launcher for a user                                                                                                     | Confirm they're assigned `Extole_App_Admin` or `Extole_App_Viewer` (Setup → Permission Sets → the set → Manage Assignments). If assigned and still missing, redeploy the permission set — its `applicationVisibilities` grant may not have deployed.                                                                                                                                             |
| "You do not have access to the Apex class named '...'" error on any tab                                                                                  | The user's assigned permission set doesn't grant that class. Check Setup → Permission Sets → the set → Apex Class Access.                                                                                                                                                                                                                                                                        |
| A tab renders but shows no data (e.g. "No live Extole programs found") with no explicit error                                                            | The LWC may be silently swallowing a permission exception rather than surfacing it. Check the user's actual Apex debug log (Setup → Debug Logs, add a trace flag on their user) for the real error before assuming it's a data issue — this exact symptom was caused by a missing **read** permission on the standard `UserExternalCredential` object, not by the Extole API or the data itself. |
| Receive Extole Events shows no incoming events                                                                                                           | Confirm the Connected App's Client Credentials flow is enabled and its Consumer Key/Secret match the Extole component's `CLIENT_KEY` setting (see Step 10). Check the Event Log on the tab for delivery attempts and errors.                                                                                                                                                                     |
| Extole webhook dispatch returns `401 INVALID_SESSION_ID`, even though the Connected App's token exchange succeeds when tested directly (e.g. via `curl`) | The webhook's request script is likely built from `context.createRequestBuilder()` instead of `context.createRequestBuilderWithDefaults()` — only the latter attaches the `CLIENT_KEY`'s Authorization header. This produces a request that looks correct in every other way (right URL, right body) but is silently unauthenticated.                                                            |

For detailed diagnostics, enable **Debug Logging** on the **Send Extole Events** tab and check the KPI Data Import Log on the **Configure KPIs** tab.
