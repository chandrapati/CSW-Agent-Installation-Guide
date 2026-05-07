# SCCM application detection script for the CSW Windows agent.
#
# Cisco Secure Workload 4.0 documents the Windows service as
# CswAgent (display name "Cisco Secure Workload Deep Visibility").
#
# Returns success (writes to STDOUT) only if all checks pass:
#   1. The CswAgent service exists
#   2. The service is in Running state
#   3. The documented CSW 4.0 agent binary is present on disk
#
# SCCM treats any STDOUT output as "installed"; no output means
# "not installed".

$ErrorActionPreference = 'SilentlyContinue'

# 1. Service check
$service = Get-Service -Name 'CswAgent' -ErrorAction SilentlyContinue

if ($null -eq $service) {
    exit 0
}

if ($service.Status -ne 'Running') {
    exit 0
}

# 2. Binary check — Cisco 4.0 documents CswEngine.exe and
# TetEnfC.exe in the install directory. The default install path
# is C:\Program Files\Cisco Tetration unless your installer was
# run with a custom install folder.
$candidateBinaries = @(
    "$env:PROGRAMFILES\Cisco Tetration\CswEngine.exe",
    "$env:PROGRAMFILES\Cisco\Tetration\CswEngine.exe"
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
