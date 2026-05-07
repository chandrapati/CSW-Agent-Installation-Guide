#!/bin/bash
# GCP startup script — install CSW sensor on RHEL 9 GCE.
# Pattern A from cloud/03-gcp-startup-script.md (CSW-generated
# installer script from private GCS bucket).
#
# The instance must launch with a service account that has:
#   - roles/storage.objectViewer on the installer bucket
# OAuth scope: --scopes=cloud-platform

set -euxo pipefail
exec > /var/log/csw-startup.log 2>&1

# Idempotency — startup-script runs every boot in GCP
if [[ -f /var/lib/csw-installed ]]; then
  echo "CSW agent already installed; nothing to do."
  exit 0
fi

readonly INSTALLER_URL="https://storage.googleapis.com/internal-csw-agents/linux/tetration_linux_installer.sh"

# OAuth token from metadata server
TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

# Pull Cisco-generated installer. Treat this script as a secret
# because it embeds activation material.
curl -s -L -H "Authorization: Bearer $TOKEN" \
  -o /tmp/tetration_linux_installer.sh "$INSTALLER_URL"

chmod 700 /tmp/tetration_linux_installer.sh
bash /tmp/tetration_linux_installer.sh

rm -f /tmp/tetration_linux_installer.sh
touch /var/lib/csw-installed
echo "CSW sensor install complete at $(date -u +%FT%TZ)"
