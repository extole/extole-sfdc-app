# Extole SFDC App — Installation Guide

## Prerequisites

- **Git** with GitHub SSH access configured — [GitHub SSH setup docs](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- **Salesforce CLI** (`sf`) installed and authenticated to the target org:
  ```bash
  sf org login web        # opens browser to authenticate
  sf org list             # shows your orgs and their aliases
  ```
- **jq** installed (`brew install jq` on macOS)
- **Extole API token** — generate a long-lived token from the [Extole Security Center](https://my.extole.com/security-center) ([docs](https://dev.extole.com/docs/generate-long-lived-access-tokens))
- Installing user must be a Salesforce admin with:
  - Author Apex permission
  - Customize Application permission

---

## Step 1 — Deploy the package

```bash
sf project deploy start --target-org <org_alias>
```

Replace `<org_alias>` with the alias shown in `sf org list`. Deploys all Apex classes, LWCs, custom objects, permission sets, and the Extole app.

---

## Step 2 — Configure the Extole API credential

The app calls the Extole API using a Named Credential. This requires a long-lived Extole access token.

**Set the bearer token on the External Credential**

The `Extole_API` External Credential ships with a placeholder value. Replace it:

1. Setup → Named Credentials → **External Credentials** tab
2. Click **Extole API** → Edit
3. Under **Authentication Parameters**, find the `Authorization` parameter
4. Replace `REPLACE_WITH_BEARER_TOKEN` with: `Bearer <your_token>`
5. Save

> **If you have the Extole CLI:** run `extole ping` to verify the token is valid before continuing.

---

## Step 3 — Create the External Client App (Connected App)

The Event Configurator deploys Salesforce Flows via the Tooling API. This requires an OAuth-connected app.

1. Setup → **External Client App Manager** → **New External Client App**
   _(If you don't see External Client App Manager, use Setup → **App Manager** → **New Connected App** instead)_
2. Fill in:
   - **App Name:** `Extole Deployer`
   - **API Name:** `Extole_Deployer`
   - **Distribution:** Local
3. Under **App Settings**:
   - **Callback URL:** `https://login.salesforce.com/services/oauth2/callback`
   - **OAuth Scopes** — add:
     - **Manage user data via APIs (api)**
     - **Perform requests at any time (refresh_token, offline_access)**
4. Under **OAuth Settings → Flow Enablement**, check:
   - **Enable Authorization Code and Credentials Flow**
5. Save — the app is enabled immediately

---

## Step 4 — Run the Tooling credential setup script

After creating the Connected App, run the setup script. It will prompt you for the Consumer Key and Secret, then deploy the Auth Provider and Named Credential.

```bash
bash scripts/setup_named_credential.sh --target-org <org_alias>
```

**What the script does:**
1. Retrieves your org domain URL
2. Prompts for the Consumer Key and Secret from the app you created in Step 3
   - Find them: Setup → App Manager → Extole Deployer → View
3. Writes and deploys the `Extole_Tooling_Auth` Auth Provider and `Extole_Tooling` Named Credential

> **Note:** Salesforce does not allow setting the Consumer Secret via metadata deploy. After the script completes, it will print your secret — add it manually:
> Setup → **Auth Providers** → **Extole Tooling Auth** → Edit → paste the Consumer Secret → Save

---

## Step 5 — Authorize the Tooling credential (one-time OAuth)

After the script completes, an admin must authorize the credential:

1. Setup → **Named Credentials** → **External Credentials** tab
2. Click **Extole Tooling Cred**
3. Under **Principals**, click **Authenticate** next to the Admin principal
4. Log in with the admin account (must have Author Apex + Customize Application)
5. Approve the OAuth consent screen

This is a one-time step. After authorization, the Event Configurator can deploy Flows without requiring a browser session.

> The setup script automatically grants the `Extole_App_Admin` permission set access to the Tooling credential as part of Step 6.

---

## Step 6 — Assign permission sets

| Permission Set | Assign to |
|---|---|
| `Extole_App_Admin` | Admins who will configure the integration |
| `Extole_App_Viewer` | Any user who needs read access to the KPI Dashboard |

**Assign to yourself first** so you can access the app, then assign to any other users as needed.

```bash
# Assign to yourself
sf org assign permset --name Extole_App_Admin --target-org <org_alias>

# Assign to another user
sf org assign permset --name Extole_App_Admin --on-behalf-of <username> --target-org <org_alias>
```

---

## Step 7 — Launch and complete onboarding

1. Open the **Extole** app from the App Launcher
2. The Getting Started screen will appear on first launch — it summarizes the setup steps
3. Click **Go to Settings**
4. In **Settings → API Connection**, click **Test Connection** — verify it shows "Connected"
5. In **Settings → Report Configuration**, click **Add Report** and configure your first KPI
   - The reports you add here must already exist and be scheduled in the Extole platform — if a report hasn't run yet in Extole, the sync will return no data
6. Trigger a manual sync — your KPI Dashboard will populate once the first sync completes

> **If you have the Extole CLI:** run `extole events stream` and then trigger a Salesforce record change (e.g. create a Lead). You should see the event arrive in Extole in real time, confirming the full end-to-end flow.

---

## Optional — Extole CLI

If you have access to the Extole CLI (via npm or the private repo), install it and authenticate with your Extole API token. It's useful for verifying connectivity and watching events arrive in real time during testing.

```bash
# Install (method depends on your access — npm or private GitHub repo)
npm install -g @extole/cli                    # if published to npm
npm install -g github:cduskin-cpu/extole-cli  # if installing from the private repo

# Authenticate with your Extole API token
extole auth login --token <your_token>

# Verify connectivity
extole ping

# List available reports (confirms the token has the right scopes)
extole reports list

# Watch events arrive in real time after triggering a Salesforce record change
extole events stream
```

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| "Test Connection" fails | Bearer token is wrong, missing, or expired. Re-check Step 2b. |
| Event Configurator deploy fails | Tooling OAuth not completed. Re-check Step 5. |
| Scheduled sync not running | Go to Settings, change the Sync Cadence and save to re-register the job. |
| Permission errors on objects | User missing the `Extole_App_Admin` or `Extole_App_Viewer` permission set. |

For detailed diagnostics, enable **Debug Logging** in Settings and check the Sync Log entries.
