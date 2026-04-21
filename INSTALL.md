# Extole SFDC App — Installation Guide

## Prerequisites

- **Git** with GitHub SSH access configured — [GitHub SSH setup docs](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- **Salesforce CLI** (`sf`) installed — [Install guide](https://developer.salesforce.com/tools/salesforcecli)
- **jq** installed (`brew install jq` on macOS)
- **python3** installed (standard on macOS)
- **Extole API token** — generate a long-lived token from the [Extole Security Center](https://my.extole.com/security-center) ([docs](https://dev.extole.com/docs/generate-long-lived-access-tokens))
- Installing user must be a Salesforce admin with:
  - Author Apex permission
  - Customize Application permission

---

## Step 1 — Clone the repository and authenticate

**In your terminal:**

```bash
git clone git@github.com:cduskin-cpu/extole-sfdc-app.git
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

Assign `Extole_App_Admin` to yourself and any other admins who will configure the KPI Dashboard or the events sent to Extole:

```bash
sf org assign permset --name Extole_App_Admin --target-org <alias>
```

Assign `Extole_App_Viewer` to any user who needs read access to the KPI Dashboard and List View:

```bash
sf org assign permset --name Extole_App_Viewer --target-org <alias>
```

To assign to another user, add `--on-behalf-of <username>` to either command.

> **Recommended for production orgs:** Create a dedicated Integration User (a non-human Salesforce user with a full license) and assign it `Extole_App_Admin`. Perform the Tooling API OAuth authorization in Step 6 while logged in as that user. This ensures the Event Configurator remains functional even if the original admin's account is deactivated or their session expires.

**Also in Salesforce Setup UI** — make the Extole app visible in the App Launcher:

1. Setup → **App Manager** → find **Extole** → click the row action → **Edit**
2. Click **User Profiles** in the left menu → add the profiles that need access (e.g. System Administrator)
3. Save

---

## Step 8 — Launch and complete onboarding

1. Open the **Extole** app from the App Launcher (grid icon, top left)
2. The Getting Started screen will appear on first launch
3. Click **Go to Settings**
4. In **Settings → API Connection**, click **Test Connection** — verify it shows "Connected"
5. In **Settings → Report Configuration**, click **Add KPI** and configure your first KPI
   - Reports must already exist and be scheduled in the Extole platform — if a report hasn't run yet, the sync will return no data
6. Trigger a manual sync — your KPI Dashboard will populate once the first sync completes

> **If you have the Extole CLI:** run `extole events stream` and then trigger a Salesforce record change (e.g. create a Lead). You should see the event arrive in Extole in real time.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `InvalidProjectWorkspaceError` on deploy | You are not inside the cloned repo directory. Run `cd extole-sfdc-app` first. |
| "Test Connection" fails | Bearer token wrong, missing, or expired. Re-check Step 3. |
| Event Configurator deploy fails | Tooling OAuth not completed. Re-check Step 6. |
| Scheduled sync not running | Go to Settings, change Sync Cadence and save to re-register the job. |
| Permission errors on objects | User missing `Extole_App_Admin` or `Extole_App_Viewer` permission set. |

For detailed diagnostics, enable **Debug Logging** in Settings and check the Sync Log entries.
