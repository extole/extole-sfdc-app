#!/usr/bin/env bash
# =============================================================================
# setup_named_credential.sh
#
# Sets up the Extole_Tooling Named Credential for Salesforce-to-Salesforce
# callouts (Tooling API / Metadata API).
#
# Run this ONCE after the initial org deploy. Requires:
#   - sf CLI (Salesforce CLI) authenticated to the target org
#   - jq installed (brew install jq)
#
# Usage:
#   ./scripts/setup_named_credential.sh [--target-org <alias>]
#
# What it does:
#   1. Deploys the Extole_Deployer Connected App (if not already deployed)
#   2. Queries the auto-generated Consumer Key for that Connected App
#   3. Writes Extole_Tooling_Auth.authProvider-meta.xml with the real key
#   4. Writes Extole_Tooling.namedCredential-meta.xml with the org domain endpoint
#   5. Deploys the AuthProvider and NamedCredential
#   6. Prints instructions for the one-time admin OAuth authorization step
# =============================================================================

set -u

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

echo "=== Step 1: External Client App check ==="
echo "The External Client App must be created manually in Setup before running this script."
echo "If you haven't done this yet:"
echo "  1. Go to Setup → App Manager → New External Client App"
echo "  2. Name: 'Extole Deployer'  API Name: 'Extole_Deployer'  Distribution: Local"
echo "  3. Under OAuth Settings → Flow Enablement:"
echo "     check 'Enable Authorization Code and Credentials Flow'"
echo "  4. Callback URL: https://login.salesforce.com/services/oauth2/callback"
echo "  5. Save — the app will be enabled immediately (no wait needed)"
echo ""
echo "Press ENTER to continue (assuming Connected App already exists)..."
read -r

echo ""
echo "=== Step 2: Retrieving Consumer Key and Org Domain ==="

# Query the org domain URL
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

# External Client Apps don't expose credentials via SOQL — prompt directly.
echo "Find both values: Setup → App Manager → Extole Deployer → View → Consumer Key and Secret"
echo ""
read -rp "Paste the Consumer Key here: " CONSUMER_KEY
if [[ -z "$CONSUMER_KEY" ]]; then
    echo "ERROR: Consumer Key is required." >&2
    exit 1
fi
echo "Consumer Key: ${CONSUMER_KEY:0:8}... (truncated)"
read -rsp "Paste the Consumer Secret here (hidden): " CONSUMER_SECRET
echo ""
if [[ -z "$CONSUMER_SECRET" ]]; then
    echo "ERROR: Consumer Secret is required." >&2
    exit 1
fi
echo "Consumer Secret: (captured, hidden)"

echo ""
echo "=== Step 3: Writing AuthProvider metadata ==="

AUTH_PROVIDER_FILE="$METADATA_DIR/authproviders/Extole_Tooling_Auth.authprovider-meta.xml"
cat > "$AUTH_PROVIDER_FILE" <<AUTHXML
<?xml version="1.0" encoding="UTF-8"?>
<AuthProvider xmlns="http://soap.sforce.com/2006/04/metadata">
    <friendlyName>Extole Tooling Auth</friendlyName>
    <providerType>Salesforce</providerType>
    <consumerKey>${CONSUMER_KEY}</consumerKey>
    <consumerSecret>${CONSUMER_SECRET}</consumerSecret>
    <defaultScopes>full refresh_token</defaultScopes>
</AuthProvider>
AUTHXML
echo "Written: $AUTH_PROVIDER_FILE"

echo ""
echo "=== Step 4: Writing External Credential + Named Credential metadata ==="

mkdir -p "$METADATA_DIR/externalCredentials"

EC_FILE="$METADATA_DIR/externalCredentials/Extole_Tooling_Cred.externalCredential-meta.xml"
cat > "$EC_FILE" <<ECXML
<?xml version="1.0" encoding="UTF-8"?>
<ExternalCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <authenticationProtocol>Oauth</authenticationProtocol>
    <authProvider>Extole_Tooling_Auth</authProvider>
    <label>Extole Tooling Cred</label>
    <principalType>NamedPrincipal</principalType>
    <principals>
        <principalName>Admin</principalName>
        <sequenceNumber>1</sequenceNumber>
    </principals>
</ExternalCredential>
ECXML
echo "Written: $EC_FILE"

NC_FILE="$METADATA_DIR/namedCredentials/Extole_Tooling.namedCredential-meta.xml"
cat > "$NC_FILE" <<NCXML
<?xml version="1.0" encoding="UTF-8"?>
<NamedCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Extole Tooling</label>
    <endpoint>${ORG_DOMAIN}/services/data/v59.0/tooling</endpoint>
    <externalCredential>Extole_Tooling_Cred</externalCredential>
    <calloutStatus>Enabled</calloutStatus>
    <generateAuthorizationHeader>true</generateAuthorizationHeader>
</NamedCredential>
NCXML
echo "Written: $NC_FILE"

echo ""
echo "=== Step 5: Deploying AuthProvider + External Credential + Named Credential ==="
sf project deploy start \
    --source-dir "$METADATA_DIR/authproviders" \
    --source-dir "$METADATA_DIR/externalCredentials" \
    --source-dir "$METADATA_DIR/namedCredentials" \
    $ORG_FLAG

echo ""
echo "================================================================"
echo "SETUP COMPLETE — One-time authorization required:"
echo ""
echo "  1. In Salesforce Setup → Named Credentials → External Credentials tab"
echo "  2. Click 'Extole Tooling Cred'"
echo "  3. Under Principals, click 'Authenticate' next to the Admin principal"
echo "  4. Log in with an admin account that has 'Customize Application' permission"
echo "  5. Approve the OAuth prompt"
echo ""
echo "After authorization, the Event Configurator can deploy Flows without"
echo "any session token in the browser."
echo "================================================================"
