#!/usr/bin/env bash
# =============================================================================
# setup_named_credential.sh
#
# Sets up the Extole_Tooling Named Credential for Salesforce-to-Salesforce
# callouts (Tooling API / Metadata API).
#
# Run this ONCE after the initial org deploy (Step 5 in INSTALL.md).
# Requires: sf CLI authenticated to the target org, jq, python3.
#
# Usage:
#   bash scripts/setup_named_credential.sh --target-org <alias>
# =============================================================================

set -euo pipefail

TARGET_ORG=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --target-org|-o) TARGET_ORG="$2"; shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

ORG_FLAG=""
if [[ -n "$TARGET_ORG" ]]; then
    ORG_FLAG="--target-org $TARGET_ORG"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
METADATA_DIR="$PROJECT_DIR/force-app/main/default"

# All metadata writes go to a temp directory — force-app/ is never modified
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/authproviders" "$WORK_DIR/namedCredentials" "$WORK_DIR/permissionsets"

echo "=== Step 1: Confirm External Client App exists ==="
echo ""
echo "Before continuing, confirm you have completed Step 4 in INSTALL.md:"
echo "the Extole Deployer External Client App must exist in Salesforce Setup."
echo ""
echo "Press ENTER to continue..."
read -r

echo ""
echo "=== Step 2: Retrieving org domain ==="

ORG_DOMAIN=$(sf org display $ORG_FLAG --json 2>/dev/null | jq -r '.result.instanceUrl' 2>/dev/null)
if [[ -z "$ORG_DOMAIN" || "$ORG_DOMAIN" == "null" ]]; then
    echo "Could not retrieve org domain automatically."
    read -rp "Paste your org domain URL (e.g. https://myorg.sandbox.my.salesforce.com): " ORG_DOMAIN
    if [[ -z "$ORG_DOMAIN" ]]; then
        echo "ERROR: Org domain is required." >&2
        exit 1
    fi
fi
echo "Org domain: $ORG_DOMAIN"

echo ""
echo "=== Step 3: Consumer Key and Secret ==="
echo ""
echo "Find these values in Salesforce Setup:"
echo "  External Client App Manager → Extole Deployer → Settings tab → OAuth Settings → Consumer Key and Secret"
echo ""
read -rp "Paste the Consumer Key: " CONSUMER_KEY
if [[ -z "$CONSUMER_KEY" ]]; then
    echo "ERROR: Consumer Key is required." >&2
    exit 1
fi
echo "Consumer Key: ${CONSUMER_KEY:0:8}... (truncated)"
read -rsp "Paste the Consumer Secret (input hidden): " CONSUMER_SECRET
echo ""
if [[ -z "$CONSUMER_SECRET" ]]; then
    echo "ERROR: Consumer Secret is required." >&2
    exit 1
fi
echo "Consumer Secret: (captured)"

echo ""
echo "=== Step 4: Deploying Auth Provider ==="

cat > "$WORK_DIR/authproviders/Extole_Tooling_Auth.authprovider-meta.xml" <<AUTHXML
<?xml version="1.0" encoding="UTF-8"?>
<AuthProvider xmlns="http://soap.sforce.com/2006/04/metadata">
    <friendlyName>Extole Tooling Auth</friendlyName>
    <providerType>Salesforce</providerType>
    <consumerKey>${CONSUMER_KEY}</consumerKey>
    <defaultScopes>api refresh_token</defaultScopes>
</AuthProvider>
AUTHXML

sf project deploy start \
    --source-dir "$WORK_DIR/authproviders" \
    $ORG_FLAG

echo ""
echo "=== Step 5: Update callback URL in the External Client App ==="
echo ""
echo "In Salesforce Setup UI:"
echo ""
echo "  1. Setup → Auth Providers → Extole Tooling Auth"
echo "     Copy the Callback URL shown on the detail page."
echo "     It will look like:"
echo "     ${ORG_DOMAIN}/services/authcallback/Extole_Tooling_Auth"
echo ""
echo "  2. Setup → External Client App Manager → Extole Deployer → Edit"
echo "     Replace the Callback URL with the value you just copied → Save"
echo ""
echo "Press ENTER once you have updated the Callback URL..."
read -r

echo ""
echo "=== Step 6: Create External Credential ==="
echo ""
echo "In Salesforce Setup UI:"
echo ""
echo "  Setup → Named Credentials → External Credentials tab → New"
echo ""
echo "  Fill in:"
echo "    Label:                    Extole Tooling Cred"
echo "    API Name:                 Extole_Tooling_Cred"
echo "    Authentication Protocol:  OAuth 2.0"
echo "    Authentication Flow Type: Browser Flow"
echo "    Identity Provider:        change the dropdown from 'External Auth Identity Provider'"
echo "                              to 'Auth Provider', then select 'Extole Tooling Auth'"
echo "    Scope:                    (leave blank)"
echo "  Save."
echo ""
echo "  Then on the credential detail page, under Principals → New:"
echo "    Parameter Name:  Admin"
echo "    Identity Type:   Named Principal"
echo "    Scope:           (leave blank)"
echo "  Save."
echo ""
echo "Press ENTER once you have created the External Credential and added the principal..."
read -r

echo ""
echo "=== Step 7: Deploying Named Credential ==="

cat > "$WORK_DIR/namedCredentials/Extole_Tooling.namedCredential-meta.xml" <<NCXML
<?xml version="1.0" encoding="UTF-8"?>
<NamedCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Extole Tooling</label>
    <endpoint>${ORG_DOMAIN}/services/data/v59.0/tooling</endpoint>
    <externalCredential>Extole_Tooling_Cred</externalCredential>
    <calloutStatus>Enabled</calloutStatus>
    <generateAuthorizationHeader>true</generateAuthorizationHeader>
</NamedCredential>
NCXML

sf project deploy start \
    --source-dir "$WORK_DIR/namedCredentials" \
    $ORG_FLAG

echo ""
echo "=== Step 8: Granting credential access to Extole_App_Admin permission set ==="

python3 - "$METADATA_DIR/permissionsets/Extole_App_Admin.permissionset-meta.xml" \
          "$WORK_DIR/permissionsets/Extole_App_Admin.permissionset-meta.xml" <<'PYEOF'
import sys
with open(sys.argv[1], 'r') as f:
    content = f.read()

new_block = (
    '\n    <externalCredentialPrincipalAccesses>'
    '\n        <enabled>true</enabled>'
    '\n        <externalCredentialPrincipal>Extole_Tooling_Cred-Admin</externalCredentialPrincipal>'
    '\n    </externalCredentialPrincipalAccesses>'
)
# Insert after the first closing tag (the Extole_API entry)
content = content.replace('</externalCredentialPrincipalAccesses>', '</externalCredentialPrincipalAccesses>' + new_block, 1)

with open(sys.argv[2], 'w') as f:
    f.write(content)
PYEOF

sf project deploy start \
    --source-dir "$WORK_DIR/permissionsets" \
    $ORG_FLAG

echo ""
echo "=== Step 9: Add Consumer Secret ==="
echo ""
echo "Salesforce does not allow setting the Consumer Secret via metadata deploy."
echo "Add it manually now:"
echo ""
echo "  Setup → Auth Providers → Extole Tooling Auth → Edit"
echo "  Consumer Secret: ${CONSUMER_SECRET}"
echo "  Save"

echo ""
echo "================================================================"
echo "SETUP COMPLETE"
echo ""
echo "One final step — authorize the credential (Step 6 in INSTALL.md):"
echo ""
echo "  Setup → Named Credentials → External Credentials tab"
echo "  → Extole Tooling Cred → Authenticate next to the Admin principal"
echo "================================================================"
