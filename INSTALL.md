# Extole SFDC App — Installation Guide

## Prerequisites

- **Salesforce CLI** (`sf`) installed and authenticated to the target org
- **jq** installed (`brew install jq` on macOS)
- Installing user must be a Salesforce admin with:
  - Author Apex permission
  - Customize Application permission

---

## Step 1 — Deploy the package

```bash
sf project deploy start --target-org <org_alias>
```

Deploys all Apex classes, LWCs, custom objects, permission sets, and the Extole app.

---

## Step 2 — Configure the Extole API credential

The app calls the Extole API using a Named Credential. This requires a long-lived Extole access token.

**2a. Get your Extole API token**

1. Go to [Extole Security Center](https://my.extole.com/security-center)
2. Generate a long-lived access token ([docs](https://dev.extole.com/docs/generate-long-lived-access-tokens))
3. Copy the token — you will need it in the next step

**2b. Set the bearer token on the External Credential**

The `Extole_API` External Credential ships with a placeholder value. Replace it:

1. Setup → Named Credentials → **External Credentials** tab
2. Click **Extole API** → Edit
3. Under **Authentication Parameters**, find the `Authorization` parameter
4. Replace `REPLACE_WITH_BEARER_TOKEN` with: `Bearer <your_token>`
5. Save

---

## Step 3 — Create the External Client App (Connected App)

The Event Configurator deploys Salesforce Flows via the Tooling API. This requires an OAuth-connected app.

1. Setup → **External Client App Manager** → **New External Client App**
2. Fill in:
   - **App Name:** `Extole Deployer`
   - **API Name:** `Extole_Deployer`
   - **Distribution:** Local
3. Under **OAuth Settings → Flow Enablement**, check:
   - **Enable Authorization Code and Credentials Flow**
4. **Callback URL:** `https://login.salesforce.com/services/oauth2/callback`
5. Save — the app is enabled immediately

---

## Step 4 — Run the Tooling credential setup script

After creating the Connected App, run the setup script. It will prompt you for the Consumer Key and Secret, then deploy the Auth Provider and Named Credential.

```bash
./scripts/setup_named_credential.sh --target-org <org_alias>
```

**What the script does:**
1. Retrieves your org domain URL
2. Prompts for the Consumer Key and Secret from the app you created in Step 3
   - Find them: Setup → App Manager → Extole Deployer → View
3. Writes and deploys the `Extole_Tooling_Auth` Auth Provider and `Extole_Tooling` Named Credential

---

## Step 5 — Authorize the Tooling credential (one-time OAuth)

After the script completes, an admin must authorize the credential:

1. Setup → **Named Credentials** → **External Credentials** tab
2. Click **Extole Tooling Cred**
3. Under **Principals**, click **Authenticate** next to the Admin principal
4. Log in with the admin account (must have Author Apex + Customize Application)
5. Approve the OAuth consent screen

This is a one-time step. After authorization, the Event Configurator can deploy Flows without requiring a browser session.

---

## Step 6 — Assign permission sets

| Permission Set | Assign to |
|---|---|
| `Extole_App_Admin` | Admins who will configure the integration |
| `Extole_App_Viewer` | Any user who needs read access to the KPI Dashboard |

```bash
# Example via CLI
sf org assign permset --name Extole_App_Admin --on-behalf-of <username> --target-org <org_alias>
```

---

## Step 7 — Launch and complete onboarding

1. Open the **Extole** app from the App Launcher
2. The Getting Started screen will appear on first launch — it summarizes the setup steps
3. Click **Go to Settings**
4. In **Settings → API Connection**, click **Test Connection** — verify it shows "Connected"
5. In **Settings → Report Configuration**, click **Add Report** and configure your first KPI
6. Trigger a manual sync — your KPI Dashboard will populate once the first sync completes

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| "Test Connection" fails | Bearer token is wrong, missing, or expired. Re-check Step 2b. |
| Event Configurator deploy fails | Tooling OAuth not completed. Re-check Step 5. |
| Scheduled sync not running | Go to Settings, change the Sync Cadence and save to re-register the job. |
| Permission errors on objects | User missing the `Extole_App_Admin` or `Extole_App_Viewer` permission set. |

For detailed diagnostics, enable **Debug Logging** in Settings and check the Sync Log entries.
