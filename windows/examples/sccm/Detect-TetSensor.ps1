# SCCM application detection script for the CSW Windows agent.
#
# Cisco's 4.0 documentation references TWO service names depending on
# the agent release in use:
#   * CswAgent  — current releases (display name "Cisco Secure
#                 Workload Deep Visibility")
#   * TetSensor — older releases
# This script accepts either, so it works during a phased upgrade.
#
# Returns success (writes to STDOUT) only if all checks pass:
#   1. One of the supported services exists
#   2. That service is in Running state
#   3. A known agent binary is present on disk (CswEngine.exe on
#      current releases; TetSensor.exe / tetsen.exe on older ones)
#
# SCCM treats any STDOUT output as "installed"; no output means
# "not installed".

$ErrorActionPreference = 'SilentlyContinue'

# 1. Service check — accept either current or legacy name
$service = Get-Service -Name 'CswAgent','TetSensor' -ErrorAction SilentlyContinue |
           Select-Object -First 1

if ($null -eq $service) {
    exit 0
}

if ($service.Status -ne 'Running') {
    exit 0
}

# 2. Binary check — at least one of the documented binaries should
# be on disk. Install root has shifted across releases:
#   * older: %PROGRAMFILES%\Cisco\Tetration
#   * newer: %PROGRAMFILES%\Cisco Tetration  (note: no backslash before "Tetration")
# Confirm the actual path on your fleet from your Cisco support
# contact / release notes before locking this script down.
$candidateBinaries = @(
    "$env:PROGRAMFILES\Cisco Tetration\CswEngine.exe",
    "$env:PROGRAMFILES\Cisco\Tetration\CswEngine.exe",
    "$env:PROGRAMFILES\Cisco Tetration\TetSensor.exe",
    "$env:PROGRAMFILES\Cisco\Tetration\TetSensor.exe",
    "$env:PROGRAMFILES\Cisco Tetration\tetsen.exe",
    "$env:PROGRAMFILES\Cisco\Tetration\tetsen.exe"
)
$binaryFound = $false
foreach ($p in $candidateBinaries) {
    if (Test-Path -Path $p) { $binaryFound = $true; break }
}

if (-not $binaryFound) {
    exit 0
}

# All checks passed
Write-Host ("CSW agent present and running (service: {0})" -f $service.Name)
exit 0
