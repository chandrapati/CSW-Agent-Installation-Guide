# Install-CswAgent.ps1
# GPO startup script — installs the Cisco Secure Workload (CSW) agent
# MSI silently. Runs as LocalSystem at machine boot. Idempotent.
#
# Cisco Secure Workload 4.0 documents the Windows service as
# CswAgent (display name "Cisco Secure Workload Deep Visibility").
# If you are maintaining an older Tetration-era agent that uses a
# different service name, use that release's Cisco guide and adapt
# this script intentionally.
#
# Stage this file alongside the MSI on the GPO content share, e.g.:
#   \\fileserver\CSW$\<version>\
#       Install-CswAgent.ps1
#       TetrationAgentInstaller-<version>-x64.msi
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

function Get-CswAgentService {
    Get-Service -Name 'CswAgent' -ErrorAction SilentlyContinue
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
        Write-Log "CswAgent service is not present after install."
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
