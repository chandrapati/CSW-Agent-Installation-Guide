# Windows — Verification

The Windows agent is installed. How do you confirm it's actually
working? This is the post-install checklist for Windows hosts.

> Pair these checks with the **CSW UI** (*Manage → Agents →
> Software Agents*). The UI tells you what the cluster sees; this
> doc tells you what the workload knows. Both views need to agree.

> **Naming note.** Cisco's 4.0 documentation references **two**
> Windows service names depending on the agent release:
>
> | Release | Service name | Process names |
> |---|---|---|
> | Current CSW 4.x | `CswAgent` | `CswEngine.exe` (deep visibility), `TetEnfC.exe` (enforcer) |
> | Older releases | `TetSensor` | `TetSenEngine.exe` / `tetsen.exe` / `TetSensor.exe` |
>
> The PowerShell snippets below use `'CswAgent','TetSensor'` so
> they work on both. Where a snippet still uses the bare legacy
> name, it's flagged.

---

## Five-minute health check

Run from an **elevated** PowerShell on the workload:

```powershell
# Helper — find whichever CSW agent service is installed.
$svc = Get-Service -Name 'CswAgent','TetSensor' -ErrorAction SilentlyContinue |
       Select-Object -First 1
if ($null -eq $svc) {
    Write-Host "Neither CswAgent nor TetSensor service is installed."
    return
}

# 1. Service is Running
$svc | Format-List Name, Status, StartType

# 2. Service is set to start automatically — already shown above

# 3. Process is alive — current releases use CswEngine; older use
#    TetSensor / tetsen
Get-Process -Name 'CswEngine','TetSensor','tetsen','TetSenEngine','TetEnfC' `
            -ErrorAction SilentlyContinue

# 4. Recent agent log (no errors in last 50 lines).
# Log root path can differ across releases; check both common paths.
$logRoots = @(
    "$env:ProgramData\Cisco\Tetration\Logs",
    "$env:ProgramFiles\Cisco Tetration\Logs",
    "$env:ProgramFiles\Cisco\Tetration\Logs"
) | Where-Object { Test-Path $_ }

if ($logRoots) {
    Get-ChildItem -Path $logRoots -Recurse -Filter *.log -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1 |
      Get-Content -Tail 50
}

# 5. Outbound connectivity to cluster
Test-NetConnection -ComputerName <cluster-fqdn> -Port 443 |
  Select-Object ComputerName, RemoteAddress, RemotePort, TcpTestSucceeded
```

If all five pass, the workload-side install is healthy. Cross-check
in the UI to confirm registration.

---

## Detailed verification

### 1. Confirm the agent is installed

```powershell
# Look up the installed product
Get-WmiObject -Class Win32_Product -Filter "Name LIKE 'Cisco%' OR Name LIKE '%Tetration%'" |
  Select-Object Name, Version, IdentifyingNumber, InstallDate

# Or via the registry (faster than WMI on systems with many MSIs)
$paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
$paths | ForEach-Object {
    Get-ChildItem $_ -ErrorAction SilentlyContinue |
      Get-ItemProperty -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -like '*Tetration*' -or $_.DisplayName -like '*Cisco Secure Workload*' } |
      Select-Object DisplayName, DisplayVersion, InstallDate, UninstallString
}
```

### 2. Confirm the CSW agent service is healthy

```powershell
# Accept either service name
$svc = Get-Service -Name 'CswAgent','TetSensor' -ErrorAction SilentlyContinue |
       Select-Object -First 1
$svc | Format-List *

# Detailed view: process ID, start type, dependent services
Get-CimInstance -ClassName Win32_Service `
  -Filter "Name='CswAgent' OR Name='TetSensor'" |
  Select-Object Name, State, StartMode, ProcessId, PathName
```

Expected:
- `Status: Running`
- `StartType: Automatic`
- `PathName` points into `C:\Program Files\Cisco Tetration\`,
  `C:\Program Files\Cisco\Tetration\`, or release-equivalent path

If the service is `Stopped`, attempt to start and capture errors:

```powershell
if ($svc) {
    Start-Service -Name $svc.Name -ErrorAction Continue
    Start-Sleep -Seconds 5
    Get-Service -Name $svc.Name
}
```

### 3. Confirm related services (Enforcement mode)

In Enforcement mode, additional services / drivers may be present.
Names vary by release; the install screen for your CSW version
documents them. Common pattern:

```powershell
Get-Service | Where-Object { $_.Name -like '*Tet*' -or $_.DisplayName -like '*Tetration*' -or $_.DisplayName -like '*Secure Workload*' }
```

### 4. Confirm Windows Filtering Platform integration (Enforcement)

When the agent is in Enforcement mode, it programs WFP filters.
A quick check:

```powershell
# Show WFP filters added by the CSW agent (filter names vary by release)
netsh wfp show filters file=C:\temp\wfp-filters.xml verbose=on
# Then inspect C:\temp\wfp-filters.xml — look for filters with
# providerKey or layerKey attributes referencing Tetration / Cisco
```

### 5. Confirm outbound connectivity to the cluster

```powershell
# Cluster destination per agent registry
$reg = 'HKLM:\SOFTWARE\Cisco\Tetration'
Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue |
  Format-List *

# Test the destination directly
$cluster = '<cluster-fqdn>'
Test-NetConnection -ComputerName $cluster -Port 443

# Active connections from the agent process — accept either
# current (CswEngine) or legacy (TetSensor / tetsen) process name.
$agentProc = Get-Process -Name 'CswEngine','TetSensor','tetsen','TetSenEngine' `
                         -ErrorAction SilentlyContinue
if ($agentProc) {
    $agentPids = $agentProc | Select-Object -ExpandProperty Id
    Get-NetTCPConnection -State Established |
      Where-Object { $agentPids -contains $_.OwningProcess } |
      Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort
}
```

### 6. Confirm time sync

TLS handshake fails on clock skew:

```powershell
w32tm /query /status
# Expected: Source: <a working time source>; Last Successful Sync Time: recent
```

### 7. Confirm the agent registered with the cluster

In the **CSW UI**:

1. *Manage → Agents → Software Agents*
2. Search by hostname
3. Look at the **Status** column:
   - **Running** — registered, telemetry flowing, healthy
   - **Not Active** — installed but not checking in (network /
     firewall / activation issue)
   - **Degraded** — registered with a warning

The host details panel shows last check-in, sensor type, software
version, scope, and inventory tags.

### 8. Confirm telemetry is flowing

In the **CSW UI**:

1. *Investigate → Flows*
2. Filter by the workload's IP or hostname
3. Within ~2 minutes of the service starting, you should see flows

### 9. Confirm software inventory is enriched

In the **CSW UI**:

1. *Organize → Inventory*
2. Find the workload by IP / hostname
3. The detail panel should show installed Windows applications
   (from the registry `Uninstall` keys), CVE list with severities,
   and process inventory

If software inventory is empty after 30 minutes, see the
troubleshooting doc.

---

## Verification automation snippets

### PowerShell — full check on one host

```powershell
# Verify-CswAgent.ps1 (filename kept as Verify-TetSensor.ps1 in
# many internal repos for backward compatibility — the body
# below is release-agnostic and accepts both names).
[CmdletBinding()]
param(
    [string] $ClusterFqdn = 'csw.example.com'
)

function Show-Result {
    param([string] $Label, [string] $Status, [string] $Detail = '')
    $color = switch ($Status) {
        'PASS' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
    }
    Write-Host (" {0,-5} " -f $Status) -ForegroundColor $color -NoNewline
    Write-Host $Label -NoNewline
    if ($Detail) { Write-Host "  ($Detail)" -ForegroundColor DarkGray } else { Write-Host '' }
}

# 1. Service exists and Running — accept either current
# (CswAgent) or legacy (TetSensor) name
$svc = Get-Service -Name 'CswAgent','TetSensor' -ErrorAction SilentlyContinue |
       Select-Object -First 1
if ($null -eq $svc) {
    Show-Result 'CSW agent service' 'FAIL' 'neither CswAgent nor TetSensor found'
} elseif ($svc.Status -ne 'Running') {
    Show-Result ("CSW agent service ({0})" -f $svc.Name) 'FAIL' "status: $($svc.Status)"
} else {
    Show-Result ("CSW agent service ({0})" -f $svc.Name) 'PASS' 'Running'
}

# 2. Set to Auto start
if ($svc -and $svc.StartType -eq 'Automatic') {
    Show-Result 'CSW agent StartType' 'PASS' 'Automatic'
} elseif ($svc) {
    Show-Result 'CSW agent StartType' 'WARN' "StartType=$($svc.StartType)"
}

# 3. Process alive — current releases use CswEngine; older use
# TetSensor / tetsen / TetSenEngine
$proc = Get-Process -Name 'CswEngine','TetSensor','tetsen','TetSenEngine' `
                    -ErrorAction SilentlyContinue |
        Select-Object -First 1
if ($null -ne $proc) {
    Show-Result ("CSW agent process ({0})" -f $proc.ProcessName) 'PASS' "PID $($proc.Id), WS $([int]($proc.WorkingSet/1MB)) MB"
} else {
    Show-Result 'CSW agent process' 'FAIL' 'no process'
}

# 4. Outbound to cluster
$probe = Test-NetConnection -ComputerName $ClusterFqdn -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
if ($probe) {
    Show-Result "Cluster reachability ($ClusterFqdn:443)" 'PASS' 'TCP open'
} else {
    Show-Result "Cluster reachability ($ClusterFqdn:443)" 'FAIL' 'cannot reach 443'
}

# 5. Recent log
$logRoot = "$env:ProgramData\Cisco\Tetration\Logs"
if (Test-Path -LiteralPath $logRoot) {
    $newest = Get-ChildItem -Path $logRoot -Recurse -Filter *.log -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newest) {
        $ageMin = [int]((Get-Date) - $newest.LastWriteTime).TotalMinutes
        if ($ageMin -le 10) {
            Show-Result 'Agent log freshness' 'PASS' "$ageMin min old"
        } elseif ($ageMin -le 60) {
            Show-Result 'Agent log freshness' 'WARN' "$ageMin min old"
        } else {
            Show-Result 'Agent log freshness' 'FAIL' "$ageMin min old"
        }
    } else {
        Show-Result 'Agent log presence' 'FAIL' 'no .log files in expected dir'
    }
} else {
    Show-Result 'Agent log presence' 'FAIL' "no log dir at $logRoot"
}

# 6. Time sync
$timeStatus = (w32tm /query /status) -join "`n"
if ($timeStatus -match 'Last Successful Sync Time:\s*\d') {
    Show-Result 'Time synchronisation' 'PASS' 'w32time has recent sync'
} else {
    Show-Result 'Time synchronisation' 'WARN' 'review w32tm /query /status'
}
```

---

## Common findings during verification

### "Service Running but UI says Not Active"

1. Confirm outbound 443 reaches the cluster
   (`Test-NetConnection`)
2. Confirm activation key matches the one currently valid in the
   CSW UI (regenerate from UI; reinstall)
3. Check Application Event Log — Cisco's 4.0 docs use both
   `CswAgent` (current releases) and `TetSensor` (older releases):
   ```powershell
   Get-WinEvent -LogName Application `
     -ProviderName 'CswAgent','TetSensor' -MaxEvents 100 -ErrorAction SilentlyContinue |
     Format-List TimeCreated, LevelDisplayName, Message
   ```
4. If on-prem cluster: confirm CA chain is in the agent conf
   directory and matches the cluster CA

### "Service flapping (Running → Stopped → Running)"

1. Check Windows Event Log for `Service Control Manager` entries
   noting unexpected stops:
   ```powershell
   Get-WinEvent -LogName System -FilterXPath "*[System[EventID=7034 or EventID=7031]]" -MaxEvents 50 |
     Where-Object { $_.Message -like '*CswAgent*' -or $_.Message -like '*TetSensor*' -or $_.Message -like '*Tetration*' -or $_.Message -like '*Cisco Secure Workload*' }
   ```
2. Check for EDR / Defender quarantining the agent driver
3. Open a TAC case with the evidence bundle from
   [`../operations/08-evidence-audit.md`](../operations/08-evidence-audit.md)

### "Software inventory empty in UI after 30 min"

1. The Windows inventory walk reads from registry `Uninstall`
   keys; verify those keys aren't restricted by GPO /
   AppLocker / WDAC
2. Check the agent log for inventory-related errors
3. Trigger a manual inventory refresh per the troubleshooting doc

---

## See also

- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md) — when verification fails
- [`../operations/08-evidence-audit.md`](../operations/08-evidence-audit.md) — what to gather before a TAC case
- [`../docs/04-rollout-strategy.md`](../docs/04-rollout-strategy.md) — what to verify between Monitor / Simulate / Enforce phases
