# Windows — Group Policy (GPO) Startup Script

The fallback method for domain-joined Windows fleets that don't
have SCCM or Intune available. A startup script (run by the
machine at boot under `LocalSystem`) installs the MSI silently.

> GPO startup scripts are **coarse**: no per-device retry logic,
> no compliance reporting, no inventory tracking, no built-in
> upgrade handling. Use only when SCCM ([03](./03-sccm-deployment.md))
> or Intune ([04](./04-intune-deployment.md)) is genuinely
> unavailable. For everything else, prefer those two.

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- Active Directory environment with the target hosts in a
  reachable OU
- Group Policy authoring rights on a GPO scoped to that OU
- A central UNC share readable by `Domain Computers` (or a more
  scoped group) where you'll stage the MSI:
  - `\\<domain>\NETLOGON\CSW\` — auto-replicated by AD; convenient
    for small payloads, but watch the SYSVOL replication footprint
  - `\\<file-server>\<share>$\CSW\` — preferred for production
- The CSW MSI (`TetrationAgentInstaller-3.x.y.z-x64.msi`)
  downloaded from the CSW UI for your target scope and sensor type

---

## Step 1 — Stage the MSI on the share

```powershell
# Copy MSI to the share (run as admin)
Copy-Item -Path .\TetrationAgentInstaller-3.x.y.z-x64.msi `
          -Destination \\fileserver\CSW$\3.x.y.z\

# Set ACL: read for Domain Computers
$acl = Get-Acl '\\fileserver\CSW$\3.x.y.z\TetrationAgentInstaller-3.x.y.z-x64.msi'
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    'DOMAIN\Domain Computers',
    'Read',
    'Allow'
)
$acl.AddAccessRule($rule)
Set-Acl -Path '\\fileserver\CSW$\3.x.y.z\TetrationAgentInstaller-3.x.y.z-x64.msi' -AclObject $acl
```

If you're using `\\<domain>\NETLOGON\`, AD's SYSVOL replication
distributes the file automatically, but you should confirm
replication completed before depending on it (`repadmin /replsum`).

---

## Step 2 — Author the startup script

Save as `Install-TetSensor.ps1` (also published in
[`./examples/gpo/Install-TetSensor.ps1`](./examples/gpo/Install-TetSensor.ps1)):

```powershell
# Install-TetSensor.ps1 — runs at machine startup as LocalSystem.
# Idempotent: skips work if the agent is already installed and running.

$ErrorActionPreference = 'Stop'
$logPath = "$env:WINDIR\Temp\Install-TetSensor.log"

function Write-Log($msg) {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$stamp  $msg" | Out-File -FilePath $logPath -Append -Encoding UTF8
}

# Idempotency check
$svc = Get-Service -Name 'TetSensor' -ErrorAction SilentlyContinue
if ($null -ne $svc -and $svc.Status -eq 'Running') {
    Write-Log "TetSensor already installed and running. Nothing to do."
    exit 0
}

$msiPath = '\\fileserver\CSW$\3.x.y.z\TetrationAgentInstaller-3.x.y.z-x64.msi'
$installLog = "$env:WINDIR\Temp\tetsensor-install.log"

if (-not (Test-Path -LiteralPath $msiPath)) {
    Write-Log "MSI not reachable at $msiPath — aborting."
    exit 2
}

Write-Log "Starting MSI install: $msiPath"

$args = @(
    '/i', "`"$msiPath`"",
    '/quiet',
    '/norestart',
    '/L*v', "`"$installLog`""
)
$p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru
Write-Log "msiexec exit code: $($p.ExitCode)"

if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
    # 3010 = success, reboot required (shouldn't happen for CSW agent)
    Write-Log "Install failed. See $installLog"
    exit $p.ExitCode
}

# Give the service a moment to start, then verify
Start-Sleep -Seconds 30
$svc = Get-Service -Name 'TetSensor' -ErrorAction SilentlyContinue
if ($null -eq $svc) {
    Write-Log "TetSensor service not present after install."
    exit 3
}
if ($svc.Status -ne 'Running') {
    Write-Log "TetSensor service installed but not Running (Status: $($svc.Status)). Attempting Start-Service."
    Start-Service -Name 'TetSensor'
    Start-Sleep -Seconds 10
    $svc.Refresh()
}

Write-Log "TetSensor service final status: $($svc.Status)"
exit 0
```

Place a copy of this script in the same share as the MSI
(`\\fileserver\CSW$\3.x.y.z\Install-TetSensor.ps1`).

---

## Step 3 — Create the GPO

In the Group Policy Management Console:

1. Navigate to the OU that contains your target hosts
2. Right-click → *Create a GPO in this domain, and Link it here*
3. Name: *Cisco Secure Workload Sensor — Install*
4. Right-click the new GPO → *Edit*
5. Navigate to *Computer Configuration → Policies → Windows
   Settings → Scripts (Startup/Shutdown)*
6. Open *Startup* → *PowerShell Scripts* tab → *Add*
7. Script name: `\\fileserver\CSW$\3.x.y.z\Install-TetSensor.ps1`
8. Parameters: (leave blank)
9. *OK* → *Apply*
10. (Recommended) Set *Startup script execution policy* to
    *Allow scripts to interrupt running scripts* if your environment
    has multiple startup scripts and you want the CSW one to wait
    for prior ones to finish.

---

## Step 4 — Force GPO refresh on test hosts

```powershell
# On a target host (run as admin)
gpupdate /force

# Trigger a reboot to fire the startup script
Restart-Computer -Force

# After reboot, check the startup script log
Get-Content -Path C:\Windows\Temp\Install-TetSensor.log -Tail 50
```

---

## Step 5 — Wave-based rollout via OU staging

GPO's natural unit of staging is the **OU**. Standard pattern:

| Wave | OU |
|---|---|
| Lab | `OU=CSW Sensor Wave 0,OU=Lab,DC=...` |
| Stage | `OU=CSW Sensor Wave 1,OU=Stage,DC=...` |
| Prod canary | `OU=CSW Sensor Wave 2,OU=Prod,DC=...` |
| Prod | `OU=CSW Sensor Wave 3,OU=Prod,DC=...` |

Move computer accounts between OUs (or extend the OU scoping of
the GPO) as waves progress. Reboot is required to trigger the
startup script on each newly-in-scope host.

---

## Day-2 patching cadence

Because the GPO startup script targets a specific MSI version, the
"upgrade" pattern is:

1. Stage the new version's MSI in
   `\\fileserver\CSW$\3.x.y+1.z\`
2. Update the GPO startup script to reference the new path
3. The script's idempotency check (existing service is Running)
   means it will *not* upgrade automatically — you'd need to
   either:
   - Add an explicit "uninstall the old version then install the
     new" step to the script (raises risk; rebooting at startup
     is when you don't want surprises)
   - Have a separate scheduled task that handles upgrades during
     a maintenance window

This is the **major weakness of the GPO method** for CSW. SCCM
and Intune handle in-place upgrades cleanly via supersedence; GPO
doesn't. If you're going to do many CSW agent upgrades over time,
plan for it now or adopt SCCM / Intune.

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Startup script doesn't run | GPO not applying to the OU | `gpresult /h gpresult.html` on a target; confirm the GPO is in the *Applied* list |
| Script runs but MSI install fails | Network share unreachable from `LocalSystem` context | Confirm the share's permissions include `Domain Computers` (machine accounts), not just user groups |
| Startup script runs every boot, attempts reinstall | Idempotency check failed | Confirm service name (`TetSensor`) matches your release; some older releases use a different name |
| Some hosts succeed, others timeout | Slow boot causing GPO timeout | Increase *Specify maximum wait time for Group Policy scripts*; or convert to a scheduled task that runs at boot with a longer grace period |
| GPO auditing shows the script ran but no install log | `LocalSystem` lacks write access to the temp path | Verify `C:\Windows\Temp` is writable; or change `$logPath` to a different location |

---

## When this is the right method

- **Domain-joined Windows fleets without SCCM / Intune.** GPO is
  the native Microsoft fallback.
- **Air-gapped enterprise networks** where SCCM/Intune isn't
  deployed but the AD infrastructure exists.

## When this is NOT the right method

- **You have SCCM or Intune.** Use those — they handle every
  weakness GPO has (per-device retry, compliance, supersedence).
- **You expect frequent upgrade cycles.** GPO upgrade story is
  weak; any CSW release rotation will be painful.
- **You need per-device install reporting.** GPO has no native
  inventory; you'd be writing custom reporting on top of `gpresult`
  / startup-script log scraping.

---

## See also

- [`./examples/gpo/Install-TetSensor.ps1`](./examples/gpo/Install-TetSensor.ps1) — runnable startup script
- [`03-sccm-deployment.md`](./03-sccm-deployment.md) — preferred enterprise pattern
- [`04-intune-deployment.md`](./04-intune-deployment.md) — preferred cloud-managed pattern
- [`06-verification.md`](./06-verification.md)
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md)
