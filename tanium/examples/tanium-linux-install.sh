#!/usr/bin/env bash
# Tanium / automated-deploy wrapper — validates user.cfg, then runs CSW install.
#
# Usage (Agent Image Installer — RPM/DEB in same directory):
#   sudo ./tanium-linux-install.sh /opt/tanium/csw
#
# Set CSW_INSTALL_SCRIPT if using Agent Script Installer instead of RPM/DEB:
#   export CSW_INSTALL_SCRIPT=/opt/tanium/csw/install_sensor.sh

set -euo pipefail

INSTALL_DIR="${1:-/opt/tanium/csw}"
USER_CFG="${INSTALL_DIR}/user.cfg"
LOG_FILE="${CSW_INSTALL_LOG:-/var/log/tetration/tanium-install.log}"

require_file() {
  local f="$1"
  local label="$2"
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Missing ${label}: ${f}" >&2
    exit 1
  fi
}

require_file "${USER_CFG}" "user.cfg (pre-stage activation key before install)"
grep -q '^ACTIVATION_KEY=.\+' "${USER_CFG}" || {
  echo "ERROR: user.cfg exists but ACTIVATION_KEY is empty or missing." >&2
  exit 1
}

require_file "${INSTALL_DIR}/ca.cert" "ca.cert (ship full Cisco bundle)"
require_file "${INSTALL_DIR}/site.cfg" "site.cfg"

mkdir -p "$(dirname "${LOG_FILE}")"

if [[ -n "${CSW_INSTALL_SCRIPT:-}" ]]; then
  require_file "${CSW_INSTALL_SCRIPT}" "CSW install script"
  echo "Running CSW Agent Script Installer: ${CSW_INSTALL_SCRIPT}"
  bash "${CSW_INSTALL_SCRIPT}" --logfile="${LOG_FILE}"
else
  shopt -s nullglob
  rpms=("${INSTALL_DIR}"/*.rpm)
  debs=("${INSTALL_DIR}"/*.deb)
  if ((${#rpms[@]})); then
    echo "Installing RPM from ${INSTALL_DIR}"
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y "${rpms[@]}"
    elif command -v yum >/dev/null 2>&1; then
      yum install -y "${rpms[@]}"
    else
      rpm -ivh "${rpms[@]}"
    fi
  elif ((${#debs[@]})); then
    echo "Installing DEB from ${INSTALL_DIR}"
    apt install -y "${debs[@]}"
  else
    echo "ERROR: No .rpm or .deb in ${INSTALL_DIR}. Set CSW_INSTALL_SCRIPT or add package." >&2
    exit 1
  fi
fi

systemctl enable csw-agent
systemctl start csw-agent
systemctl is-active --quiet csw-agent
echo "CSW agent install complete; csw-agent is active."
