# Intune Win32 app — detection script for the Cisco Secure Workload sensor.
#
# Behaviour:
#   - exit 0 with stdout output  → app is detected (installed and running)
#   - exit 1                     → app is not detected (Intune will install)
#
# Place a copy in your packaging source folder when wrapping the .intunewin,
# OR upload directly to the Win32 app's "Detection rules" → "Use a custom
# detection script" field.

$ErrorActionPreference = 'SilentlyContinue'

# Service must exist
$svc = Get-Service -Name 'CswAgent'
if ($null -eq $svc) {
    exit 1
}

# Service must be Running
if ($svc.Status -ne 'Running') {
    exit 1
}

# Optional: confirm the binary is on disk in the expected location.
# Adjust the path to match your CSW release's install layout.
$binaryCandidates = @(
    "$env:ProgramFiles\Cisco Tetration\TetSensor.exe",  # Note: legacy filename; newer agents use CswEngine.exe
    "$env:ProgramFiles\Cisco\Tetration\TetSensor.exe" # Note: legacy filename; newer agents use CswEngine.exe
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

Write-Output "Cisco Secure Workload agent detected: CswAgent service is Running"
exit 0
