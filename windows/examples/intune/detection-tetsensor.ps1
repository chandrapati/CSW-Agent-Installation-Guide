# Intune Win32 app — detection script for the Cisco Secure Workload
# (CSW) agent.
#
# Cisco's 4.0 documentation references TWO Windows service names
# depending on the agent release:
#   * CswAgent  — current releases (display name "Cisco Secure
#                 Workload Deep Visibility")
#   * TetSensor — older releases
# This script accepts either, so it stays valid across a phased
# fleet upgrade.
#
# Behaviour:
#   - exit 0 with stdout output  → app is detected (installed and running)
#   - exit 1                     → app is not detected (Intune will install)
#
# Place a copy in your packaging source folder when wrapping the
# .intunewin, OR upload directly to the Win32 app's "Detection
# rules" → "Use a custom detection script" field.

$ErrorActionPreference = 'SilentlyContinue'

# Service must exist — accept either current or legacy name
$svc = Get-Service -Name 'CswAgent','TetSensor' -ErrorAction SilentlyContinue |
       Select-Object -First 1
if ($null -eq $svc) {
    exit 1
}

# Service must be Running
if ($svc.Status -ne 'Running') {
    exit 1
}

# Optional: confirm the binary is on disk in the expected location.
# The agent install root has shifted across releases:
#   * older: %PROGRAMFILES%\Cisco\Tetration
#   * newer: %PROGRAMFILES%\Cisco Tetration  (note: no backslash before "Tetration")
# Process names also changed:
#   * older: TetSensor.exe / tetsen.exe
#   * newer: CswEngine.exe (deep visibility) / TetEnfC.exe (enforcer)
# Confirm the actual layout for your release with Cisco's
# documentation before locking this script down.
$binaryCandidates = @(
    "$env:ProgramFiles\Cisco Tetration\CswEngine.exe",
    "$env:ProgramFiles\Cisco\Tetration\CswEngine.exe",
    "$env:ProgramFiles\Cisco Tetration\TetSensor.exe",
    "$env:ProgramFiles\Cisco\Tetration\TetSensor.exe",
    "$env:ProgramFiles\Cisco Tetration\tetsen.exe",
    "$env:ProgramFiles\Cisco\Tetration\tetsen.exe"
)
$binaryFound = $false
foreach ($p in $binaryCandidates) {
    if (Test-Path -LiteralPath $p) {
        $binaryFound = $true
        break
    }
}
if (-not $binaryFound) {
    exit 1
}

Write-Output ("Cisco Secure Workload agent detected: service '{0}' is Running" -f $svc.Name)
exit 0
