# SCCM application detection script for the CSW Windows sensor.
#
# Returns success (writes to STDOUT) only if all three checks pass:
#   1. The TetSensor service exists
#   2. The TetSensor service is in Running state
#   3. The TetSensor binary is present on disk
#
# SCCM treats any STDOUT output as "installed"; no output means "not installed".

$ErrorActionPreference = 'SilentlyContinue'

$service = Get-Service -Name 'TetSensor' -ErrorAction SilentlyContinue
$binary  = "$env:PROGRAMFILES\Cisco\Tetration\TetSensor.exe"

if ($null -eq $service) {
    exit 0
}

if ($service.Status -ne 'Running') {
    exit 0
}

if (-not (Test-Path -Path $binary)) {
    exit 0
}

# All checks passed
Write-Host "CSW sensor present and running."
exit 0
