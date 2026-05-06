#!/usr/bin/env bash
# CSW agent first-boot activation script for Azure VMs from a baked image.
#
# Pulls the activation key from Key Vault using the VM's managed identity,
# unmasks csw-agent, and starts the service. Marker file ensures one-shot.

set -euo pipefail

MARKER=/var/lib/csw/activated
mkdir -p /var/lib/csw

if [ -f "${MARKER}" ]; then
    echo "CSW already activated; nothing to do."
    exit 0
fi

# Read tags from instance metadata (set by the deploying Terraform)
KEYVAULT_URI=$(curl -s -H Metadata:true \
  "http://169.254.169.254/metadata/instance/compute/tagsList?api-version=2021-02-01" \
  | jq -r '.[] | select(.name=="csw_keyvault_uri").value')
KEYVAULT_SECRET=$(curl -s -H Metadata:true \
  "http://169.254.169.254/metadata/instance/compute/tagsList?api-version=2021-02-01" \
  | jq -r '.[] | select(.name=="csw_keyvault_secret").value')
CLUSTER_ENDPOINT=$(curl -s -H Metadata:true \
  "http://169.254.169.254/metadata/instance/compute/tagsList?api-version=2021-02-01" \
  | jq -r '.[] | select(.name=="csw_cluster_endpoint").value')

if [ -z "${KEYVAULT_URI:-}" ] || [ -z "${KEYVAULT_SECRET:-}" ]; then
    echo "ERROR: missing csw_keyvault_uri / csw_keyvault_secret tags on this VM"
    exit 1
fi

# Get a Key Vault access token via managed identity
TOKEN=$(curl -s -H Metadata:true \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" \
  | jq -r '.access_token')

# Fetch the activation key
ACTIVATION_KEY=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
  "${KEYVAULT_URI}/secrets/${KEYVAULT_SECRET}?api-version=7.4" \
  | jq -r '.value')

if [ -z "${ACTIVATION_KEY:-}" ]; then
    echo "ERROR: failed to fetch activation key from Key Vault"
    exit 1
fi

# Render sensor.conf
mkdir -p /usr/local/tet/conf
cat > /usr/local/tet/conf/sensor.conf <<EOF
ACTIVATION_KEY=${ACTIVATION_KEY}
CLUSTER_ENDPOINT=${CLUSTER_ENDPOINT:-csw.example.com}
EOF
chmod 0640 /usr/local/tet/conf/sensor.conf

systemctl unmask csw-agent
systemctl enable --now csw-agent

# Verify
sleep 10
if systemctl is-active --quiet csw-agent; then
    echo "CSW agent activated successfully."
    touch "${MARKER}"
else
    echo "ERROR: csw-agent failed to start; check journalctl -u csw-agent"
    systemctl status csw-agent --no-pager
    exit 1
fi
