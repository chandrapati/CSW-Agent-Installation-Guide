# Intune Win32 app — detection script for the Cisco Secure Workload
# (CSW) agent.
#
# Cisco Secure Workload 4.0 documents the Windows service as
# CswAgent (display name "Cisco Secure Workload Deep Visibility").
#
# Behaviour:
#   - exit 0 with stdout output  → app is detected (installed and running)
#   - exit 1                     → app is not detected (Intune will install)
#
# Place a copy in your packaging source folder when wrapping the
# .intunewin, OR upload directly to the Win32 app's "Detection
# rules" → "Use a custom detection script" field.

$ErrorActionPreference = 'SilentlyContinue'

# Service must exist
$svc = Get-Service -Name 'CswAgent' -ErrorAction SilentlyContinue
if ($null -eq $svc) {
    exit 1
}

# Service must be Running
if ($svc.Status -ne 'Running') {
    exit 1
}

# Optional: confirm the binary is on disk in the expected location.
# Cisco 4.0 documents CswEngine.exe and TetEnfC.exe in the install
# directory. The default install path is C:\Program Files\Cisco
# Tetration unless your installer was run with a custom install
# folder.
$binaryCandidates = @(
    "$env:ProgramFiles\Cisco Tetration\CswEngine.exe",
    "$env:ProgramFiles\Cisco\Tetration\CswEngine.exe"
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
