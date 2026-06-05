# Write user.cfg from CSW_ACTIVATION_KEY before running the CSW installer.
# Intended as an early step in a Tanium Deploy package (or any CI job).
#
# Usage:
#   $env:CSW_ACTIVATION_KEY = '<key from CSW UI>'
#   optional: $env:CSW_HTTPS_PROXY = 'http://proxy:8080'
#   .\stage-user-cfg.ps1 -InstallDir 'C:\Program Files\Tanium\csw'

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'

if (-not $env:CSW_ACTIVATION_KEY) {
    Write-Error 'CSW_ACTIVATION_KEY is not set. Retrieve the key from CSW UI before install.'
}

if (-not (Test-Path -LiteralPath $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$userCfg = Join-Path $InstallDir 'user.cfg'
$lines = @("ACTIVATION_KEY=$($env:CSW_ACTIVATION_KEY)")
if ($env:CSW_HTTPS_PROXY) {
    $lines += "HTTPS_PROXY=$($env:CSW_HTTPS_PROXY)"
}

Set-Content -LiteralPath $userCfg -Value $lines -Encoding ASCII -Force

# Restrict ACL to Administrators + SYSTEM
$acl = Get-Acl -LiteralPath $userCfg
$acl.SetAccessRuleProtection($true, $false)
$acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
$adminSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'
$systemSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-18'
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid, 'FullControl', 'Allow')))
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, 'FullControl', 'Allow')))
Set-Acl -LiteralPath $userCfg -AclObject $acl

Write-Host "Wrote $userCfg (activation key staged; ready for installer)."
