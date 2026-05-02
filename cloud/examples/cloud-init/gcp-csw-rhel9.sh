#!/bin/bash
# GCP startup script — install CSW sensor on RHEL 9 GCE.
# Pattern A from cloud/03-gcp-startup-script.md (payload from private GCS bucket).
#
# The instance must launch with a service account that has:
#   - roles/storage.objectViewer on the agent bucket
#   - roles/secretmanager.secretAccessor on the activation-key secret
# OAuth scope: --scopes=cloud-platform

set -euxo pipefail
exec > /var/log/csw-startup.log 2>&1

# Idempotency — startup-script runs every boot in GCP
if [[ -f /var/lib/csw-installed ]]; then
  echo "CSW agent already installed; nothing to do."
  exit 0
fi

readonly PKG_URL="https://storage.googleapis.com/internal-csw-agents/linux/el9/tet-sensor-3.10.1.45-1.el9.x86_64.rpm"
readonly CA_URL="https://storage.googleapis.com/internal-csw-agents/linux/ca.pem"
readonly SECRET_NAME="projects/my-project/secrets/csw-activation-key-prod-web/versions/latest"
readonly CSW_SCOPE="prod:web-tier"

# OAuth token from metadata server
TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

mkdir -p /etc/tetration && chmod 750 /etc/tetration

# Pull payload
curl -s -L -H "Authorization: Bearer $TOKEN" \
  -o /tmp/tet-sensor.rpm "$PKG_URL"

curl -s -L -H "Authorization: Bearer $TOKEN" \
  -o /etc/tetration/ca.pem "$CA_URL"

# Activation key from Secret Manager
ACTIVATION_KEY=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "https://secretmanager.googleapis.com/v1/${SECRET_NAME}:access" \
  | python3 -c 'import sys,json,base64;print(base64.b64decode(json.load(sys.stdin)["payload"]["data"]).decode())')

cat > /etc/tetration/sensor.conf <<EOF
ACTIVATION_KEY=$ACTIVATION_KEY
SCOPE=$CSW_SCOPE
EOF
chmod 640 /etc/tetration/sensor.conf

dnf install -y /tmp/tet-sensor.rpm
systemctl enable --now tetd

rm -f /tmp/tet-sensor.rpm
touch /var/lib/csw-installed
echo "CSW sensor install complete at $(date -u +%FT%TZ)"
