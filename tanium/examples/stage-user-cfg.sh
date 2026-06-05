#!/usr/bin/env bash
# Write user.cfg from CSW_ACTIVATION_KEY before running the CSW installer.
# Intended as an early step in a Tanium Deploy package (or any CI job).
#
# Usage:
#   export CSW_ACTIVATION_KEY='<key from CSW UI>'
#   optional: export CSW_HTTPS_PROXY='http://proxy:8080'
#   ./stage-user-cfg.sh /opt/tanium/csw

set -euo pipefail

INSTALL_DIR="${1:-/opt/tanium/csw}"
USER_CFG="${INSTALL_DIR}/user.cfg"

if [[ -z "${CSW_ACTIVATION_KEY:-}" ]]; then
  echo "ERROR: CSW_ACTIVATION_KEY is not set. Retrieve the key from CSW UI before install." >&2
  exit 1
fi

mkdir -p "${INSTALL_DIR}"
umask 077

{
  echo "ACTIVATION_KEY=${CSW_ACTIVATION_KEY}"
  if [[ -n "${CSW_HTTPS_PROXY:-}" ]]; then
    echo "HTTPS_PROXY=${CSW_HTTPS_PROXY}"
  fi
} > "${USER_CFG}"

chmod 600 "${USER_CFG}"
echo "Wrote ${USER_CFG} (activation key staged; ready for installer)."
