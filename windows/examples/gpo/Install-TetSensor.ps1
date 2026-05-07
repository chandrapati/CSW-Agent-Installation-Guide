# Install-TetSensor.ps1
# GPO startup script — installs the Cisco Secure Workload (CSW) agent
# MSI silently. Runs as LocalSystem at machine boot. Idempotent.
#
# Cisco's 4.0 documentation references TWO Windows service names
# depending on the agent release:
#   * CswAgent  — current releases (display name "Cisco Secure
#                 Workload Deep Visibility")
#   * TetSensor — older releases
# This script accepts either, so it stays valid across a phased
# fleet upgrade.
#
# The filename is kept as `Install-TetSensor.ps1` for backward
# compatibility with anything that already references it from a
# GPO. The script body is release-agnostic.
#
# Stage this file alongside the MSI on the GPO content share, e.g.:
#   \\fileserver\CSW$\<version>\
#       Install-TetSensor.ps1
#       TetrationAgentInstaller-<version>-x64.msi   # current releases
#       (or)
#       TetSensor.msi                               # older releases
#
# Reference from: Computer Configuration → Policies → Windows Settings →
#                 Scripts (Startup/Shutdown) → Startup → PowerShell Scripts → Add

param(
    [string] $MsiSharePath = '\\fileserver\CSW$\3.x.y.z\TetrationAgentInstaller-3.x.y.z-x64.msi'
)

$ErrorActionPreference = 'Stop'
$logPath = "$env:WINDIR\Temp\Install-CswAgent.log"

function Write-Log {
    param([string] $Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$stamp  $Message" | Out-File -FilePath $logPath -Append -Encoding UTF8
}

# Helper: returns the running CSW service object (CswAgent or
# TetSensor), or $null if neither is present.
function Get-CswAgentService {
    Get-Service -Name 'CswAgent','TetSensor' -ErrorAction SilentlyContinue |
      Select-Object -First 1
}

try {
    # Idempotency check: agent already healthy?
    $svc = Get-CswAgentService
    if ($null -ne $svc -and $svc.Status -eq 'Running') {
        Write-Log ("CSW agent already installed and running (service: {0}). Nothing to do." -f $svc.Name)
        exit 0
    }

    if (-not (Test-Path -LiteralPath $MsiSharePath)) {
        Write-Log "MSI not reachable at $MsiSharePath — aborting."
        exit 2
    }

    Write-Log "Starting MSI install: $MsiSharePath"
    $installLog = "$env:WINDIR\Temp\csw-agent-install.log"

    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList @(
        '/i', "`"$MsiSharePath`"",
        '/quiet',
        '/norestart',
        '/L*v', "`"$installLog`""
    ) -Wait -PassThru
    Write-Log "msiexec exit code: $($proc.ExitCode)"

    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        Write-Log "Install failed. See $installLog"
        exit $proc.ExitCode
    }

    # Wait for the service to come up
    Start-Sleep -Seconds 30
    $svc = Get-CswAgentService
    if ($null -eq $svc) {
        Write-Log "Neither CswAgent nor TetSensor service is present after install."
        exit 3
    }
    if ($svc.Status -ne 'Running') {
        Write-Log ("Service '{0}' installed but not Running ({1}); attempting Start-Service." -f $svc.Name, $svc.Status)
        Start-Service -Name $svc.Name
        Start-Sleep -Seconds 10
        $svc.Refresh()
    }
    Write-Log ("CSW agent service final status: {0} ({1})" -f $svc.Name, $svc.Status)
    exit 0
} catch {
    Write-Log "Unhandled error: $($_.Exception.Message)"
    exit 99
}
