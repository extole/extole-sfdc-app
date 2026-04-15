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

**In Salesforce Setup UI:**

The `Extole API` External Credential ships with a placeholder bearer token. Replace it:

1. Setup → Named Credentials → **External Credentials** tab
2. Click the **Extole API** name to open the full detail page (do not click Edit — that opens a modal)
3. Under **Authentication Parameters**, find the `Authorization` row → click **Edit**
4. Replace `REPLACE_WITH_BEARER_TOKEN` with: `Bearer <your_token>`
   _(include the word `Bearer` followed by a space)_
5. Save

> **If you have the Extole CLI:** run `extole ping` to verify the token is valid before continuing.

---

## Step 4 — Create the External Client App

**In Salesforce Setup UI:**

The Event Configurator deploys Salesforce Flows via the Tooling API. This requires an OAuth app.

1. Setup → **External Client App Manager** → **New External Client App**
2. Under **Basic Information**, fill in:
   - **App Name:** `Extole Deployer`
   - **API Name:** `Extole_Deployer`
   - **Contact Email:** your admin email address
   - **Logo Image URL:** `https://www.extole.com/wp-content/uploads/2023/07/Extole-logo.svg`
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
6. Save — the app is enabled immediately

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
> 2. Setup → **External Client App Manager** → **Extole Deployer** → **Edit** → replace the Callback URL with the value you just copied → Save

**c. Create the External Credential** _(after updating the callback URL)_

> In Salesforce Setup UI:
>
> Setup → **Named Credentials** → **External Credentials** tab → **New**:
> - **Label:** `Extole Tooling Cred`
> - **API Name:** `Extole_Tooling_Cred`
> - **Authentication Protocol:** OAuth 2.0
> - **Authentication Flow Type:** Browser Flow
> - **Identity Provider:** change the dropdown from _External Auth Identity Provider_ to **Auth Provider**, then select `Extole Tooling Auth`
> - **Scope:** leave blank
>
> Save.
>
> Then on the credential detail page, under **Principals** → **New**:
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

| Permission Set | Assign to |
|---|---|
| `Extole_App_Admin` | Admins who will configure the integration |
| `Extole_App_Viewer` | Any user who needs read access to the KPI Dashboard |

Assign to yourself first, then to other users as needed:

```bash
sf org assign permset --name Extole_App_Admin --target-org <alias>
```

To assign to another user:

```bash
sf org assign permset --name Extole_App_Admin --on-behalf-of <username> --target-org <alias>
```

---

## Step 8 — Launch and complete onboarding

**In the Salesforce app:**

1. Open the **Extole** app from the App Launcher
2. The Getting Started screen will appear on first launch
3. Click **Go to Settings**
4. In **Settings → API Connection**, click **Test Connection** — verify it shows "Connected"
5. In **Settings → Report Configuration**, click **Add Report** and configure your first KPI
   - Reports must already exist and be scheduled in the Extole platform — if a report hasn't run yet, the sync will return no data
6. Trigger a manual sync — your KPI Dashboard will populate once the first sync completes

> **If you have the Extole CLI:** run `extole events stream` and then trigger a Salesforce record change (e.g. create a Lead). You should see the event arrive in Extole in real time.

---

## Optional — Extole CLI

If you have access to the Extole CLI, install it and authenticate with your Extole API token.

```bash
npm install -g github:cduskin-cpu/extole-cli

extole auth login --token <your_token>

extole ping

extole events stream
```

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
