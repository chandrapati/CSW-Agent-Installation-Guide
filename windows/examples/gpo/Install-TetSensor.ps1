# Install-TetSensor.ps1
# GPO startup script — installs the Cisco Secure Workload sensor MSI silently.
# Runs as LocalSystem at machine boot. Idempotent.
#
# Stage this file alongside the MSI on the GPO content share, e.g.:
#   \\fileserver\CSW$\3.x.y.z\
#       Install-TetSensor.ps1
#       TetrationAgentInstaller-3.x.y.z-x64.msi
#
# Reference from: Computer Configuration → Policies → Windows Settings →
#                 Scripts (Startup/Shutdown) → Startup → PowerShell Scripts → Add

param(
    [string] $MsiSharePath = '\\fileserver\CSW$\3.x.y.z\TetrationAgentInstaller-3.x.y.z-x64.msi'
)

$ErrorActionPreference = 'Stop'
$logPath = "$env:WINDIR\Temp\Install-TetSensor.log"

function Write-Log {
    param([string] $Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$stamp  $Message" | Out-File -FilePath $logPath -Append -Encoding UTF8
}

try {
    # Idempotency check: agent already healthy?
    $svc = Get-Service -Name 'CswAgent' -ErrorAction SilentlyContinue
    if ($null -ne $svc -and $svc.Status -eq 'Running') {
        Write-Log "CswAgent already installed and running. Nothing to do."
        exit 0
    }

    if (-not (Test-Path -LiteralPath $MsiSharePath)) {
        Write-Log "MSI not reachable at $MsiSharePath — aborting."
        exit 2
    }

    Write-Log "Starting MSI install: $MsiSharePath"
    $installLog = "$env:WINDIR\Temp\tetsensor-install.log"

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
    $svc = Get-Service -Name 'CswAgent' -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Log "CswAgent service not present after install."
        exit 3
    }
    if ($svc.Status -ne 'Running') {
        Write-Log "Service installed but not Running ($($svc.Status)); attempting Start-Service."
        Start-Service -Name 'CswAgent'
        Start-Sleep -Seconds 10
        $svc.Refresh()
    }
    Write-Log "CswAgent service final status: $($svc.Status)"
    exit 0
} catch {
    Write-Log "Unhandled error: $($_.Exception.Message)"
    exit 99
}
