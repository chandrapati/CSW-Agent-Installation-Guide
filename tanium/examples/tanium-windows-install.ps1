# Tanium / automated-deploy wrapper — validates user.cfg, then installs CSW MSI.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tanium-windows-install.ps1 `
#     -InstallDir 'C:\Program Files\Tanium\csw'

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir,

    [string]$MsiName = 'TetrationAgentInstaller.msi',

    [string]$LogPath = "$env:TEMP\csw-agent-tanium-install.log"
)

$ErrorActionPreference = 'Stop'

function Require-File {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing ${Label}: ${Path}"
    }
}

$userCfg = Join-Path $InstallDir 'user.cfg'
Require-File $userCfg 'user.cfg (pre-stage activation key before install)'

$content = Get-Content -LiteralPath $userCfg -Raw
if ($content -notmatch '(?m)^ACTIVATION_KEY=\S+') {
    throw 'user.cfg exists but ACTIVATION_KEY is empty or missing.'
}

Require-File (Join-Path $InstallDir 'ca.cert') 'ca.cert (ship full Cisco bundle)'
Require-File (Join-Path $InstallDir 'site.cfg') 'site.cfg'
Require-File (Join-Path $InstallDir 'sensor_config') 'sensor_config'

$msiPath = Join-Path $InstallDir $MsiName
Require-File $msiPath 'TetrationAgentInstaller.msi'

$arguments = @(
    '/i', "`"$msiPath`"",
    '/quiet',
    '/norestart',
    '/L*v', "`"$LogPath`""
)

Write-Host "Installing CSW agent from $msiPath (user.cfg validated)."
$proc = Start-Process -FilePath msiexec.exe -ArgumentList $arguments -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "msiexec failed with exit code $($proc.ExitCode). See log: $LogPath"
}

$svc = Get-Service -Name CswAgent -ErrorAction Stop
if ($svc.Status -ne 'Running') {
    Start-Service -Name CswAgent
}
if ((Get-Service -Name CswAgent).Status -ne 'Running') {
    throw 'CswAgent service is not running after install.'
}

Write-Host 'CSW agent install complete; CswAgent is running.'
