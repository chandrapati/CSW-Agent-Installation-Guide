# Windows — Manual MSI Silent Install

The simplest method: install the CSW Windows agent MSI on a single
host using `msiexec`. Use this for labs, troubleshooting, and to
learn what the agent installs.

> **Not for fleet rollout.** This method doesn't scale. For more
> than a few hosts, prefer
> [`02-csw-generated-powershell.md`](./02-csw-generated-powershell.md)
> (one host at a time but pre-configured) or one of the deployment
> platform methods (SCCM / Intune / GPO).

> **Not for VM templates / golden images.** CswAgent (legacy `TetSensor` on older releases) uses Npcap on Windows 2008 R2; modern Windows releases use the in-box `ndiscap.sys`
> for capture; NPCAP binds to the network stack at install time
> and **does not bind cleanly on VMs cloned from the template** —
> capture silently fails on every clone. Install on each VM
> post-clone via SCCM / Intune / GPO / first-boot PowerShell
> instead. See [`README.md`](./README.md) and
> [`../docs/00-official-references.md`](../docs/00-official-references.md).

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
  (specifically: **local Administrator privilege**, **≥ 1 GB**
  storage, **EDR / AV / Defender exclusions configured** —
  Defender will otherwise block the NPCAP install or quarantine
  the kernel filter driver, and the install will fail or run
  partially)
- Local administrator on the workload (the install requires it)
- The right `.msi` file for your CSW release and sensor type,
  downloaded from the CSW *Manage → Agents → Install Agent* UI
- For on-prem clusters: the cluster CA chain (`ca.pem`)
- **No conflicting NPCAP install** present on the host — if an
  unsupported NPCAP version is already installed, uninstall it
  first so the Cisco-bundled NPCAP version installs cleanly

---

## Step 1 — Download the MSI

From any host with access to the CSW UI:

1. Log into the CSW UI
2. Navigate to *Manage → Agents → Install Agent*
3. Choose **Windows** as the OS
4. Choose the **sensor type** (Deep Visibility or Enforcement)
5. Choose the **target scope** — this is baked into the MSI's
   embedded activation key
6. Click *Download package*

The downloaded file follows a naming convention similar to:

```
TetrationAgentInstaller-3.x.y.z-x64.msi
```

(Older releases name it `TetSensor.msi`; newer releases name it `TetrationAgentInstaller-x64.msi` (or release-equivalent) — check the *Manage → Workloads → Agents → Installer* screen in your cluster for the exact filename.
include the version number in the file name.)

Transfer the file to the workload (RDP file copy, SMB share,
PowerShell `Copy-Item` over a session, or your usual
file-transfer mechanism).

---

## Step 2 — (On-prem clusters only) Place the cluster CA

If the CSW cluster uses a private / internal CA, deposit the CA
chain so the agent's TLS handshake succeeds. The exact path varies
by release; the CSW *Manage → Agents → Install Agent* UI documents
the right location for your cluster. A typical path:

```powershell
# Run as Administrator
$tetConfDir = "$env:ProgramData\Cisco\Tetration\conf"
New-Item -ItemType Directory -Force -Path $tetConfDir | Out-Null
Copy-Item -Path .\ca.pem -Destination "$tetConfDir\ca.pem"
```

For SaaS clusters this step is unnecessary — public CA validation
just works.

---

## Step 3 — Install the MSI silently

Open an **elevated** Command Prompt or PowerShell session and run:

```powershell
# PowerShell (recommended — better error handling)
$msiPath = "C:\temp\TetrationAgentInstaller-3.x.y.z-x64.msi"
$logPath = "C:\temp\tetsensor-install.log"

$arguments = @(
    "/i", "`"$msiPath`"",
    "/quiet",
    "/norestart",
    "/L*v", "`"$logPath`""
)

Start-Process -FilePath msiexec.exe -ArgumentList $arguments -Wait -PassThru
```

Or in cmd.exe:

```cmd
msiexec /i "C:\temp\TetrationAgentInstaller-3.x.y.z-x64.msi" ^
  /quiet /norestart /L*v "C:\temp\tetsensor-install.log"
```

Common MSI flags:

| Flag | Purpose |
|---|---|
| `/i <msi>` | Install the package |
| `/quiet` | No UI, no prompts |
| `/norestart` | Don't auto-reboot even if the MSI marks one needed |
| `/L*v <log>` | Verbose log (essential for troubleshooting) |
| `/qn` | Alternative quiet flag (older MSI conventions) |
| `MSIEXEC_PROPERTY=value` | Pass MSI properties (cluster URL, scope, proxy) |

**Per-cluster MSI properties.** The CSW-built MSI has all the
cluster details baked in (activation key, cluster URL, scope), so
you typically don't pass any extra properties. If you need to
override, the install guide documents the property names accepted
by your release's MSI.

---

## Step 4 — Confirm the service is running

```powershell
Get-Service -Name CswAgent
```

Expected output:

```
Status   Name               DisplayName
------   ----               -----------
Running  CswAgent           Cisco Secure Workload Deep Visibility
```

You may also see related supporting services (names vary by
release). All should be in `Running` state.

---

## Step 5 — Confirm the agent registered with the cluster

In the CSW UI, *Manage → Agents → Software Agents*. The new host
should appear within 1–2 minutes of the service starting.
Initial status:

- *Running* — registered, telemetry flowing
- *Not Active* — installed but hasn't checked in (network /
  firewall issue)
- *Degraded* — registered with a warning

For deeper verification, see [`06-verification.md`](./06-verification.md).

---

## Step 6 — If something went wrong

### MSI install itself failed (non-zero exit code)

Open the verbose log:

```powershell
notepad C:\temp\tetsensor-install.log
```

Search for `Return value 3` (MSI failure marker). The line
above usually has the actual error. Common patterns:

| Symptom | Likely cause | Fix |
|---|---|---|
| `Error 1603` | Generic install failure | Read the verbose log; the line above 1603 has the real cause |
| `Error 1722` | Action failed in custom action | Often a Defender / EDR block; add allow-list exception |
| `Error 1722. There is a problem with this Windows Installer package. A program run as part of the setup did not finish as expected.` | Same as 1722 | Check Application event log for `Cisco Tetration` source |

### Service installs but won't start

```powershell
Get-WinEvent -LogName Application -MaxEvents 100 |
  Where-Object { $_.ProviderName -like '*Tet*' -or $_.Message -like '*tetsensor*' } |
  Format-Table -AutoSize TimeCreated, LevelDisplayName, ProviderName, Message
```

Common patterns:

| Symptom | Likely cause | Fix |
|---|---|---|
| `tls handshake failed: x509 unknown authority` | CA chain not deposited | Place `ca.pem` per Step 2; restart the service |
| `connection refused` / `unable to reach cluster` | Firewall / network egress | Test with `Test-NetConnection <cluster> -Port 443` |
| `unauthorized` after registration attempt | Activation key was rotated or wrong scope | Regenerate the MSI in the UI and reinstall |
| `kernel filter driver failed to load` | Driver signing / Secure Boot conflict | Confirm the driver is signed by Cisco; check Secure Boot policy |

Full troubleshooting reference:
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## Step 7 — Cleanup (if you need to start over)

See [`../operations/05-uninstall.md`](../operations/05-uninstall.md)
for the full uninstall procedure. Quick version:

```powershell
# Find the product code
Get-WmiObject -Class Win32_Product -Filter "Name LIKE 'Cisco%Workload%' OR Name LIKE '%Tetration%'" |
  Select-Object Name, IdentifyingNumber

# Uninstall by product code
$productCode = "{<GUID-from-above>}"
msiexec /x $productCode /quiet /norestart /L*v "C:\temp\tetsensor-uninstall.log"
```

The uninstall doc covers cleanup of `%ProgramData%\Cisco\Tetration\`,
the registry keys, and the agent's record in the CSW UI
(*Manage → Agents → decommission*).

---

## When NOT to use this method

- **More than ~5 hosts.** Move to the CSW-generated PowerShell
  script ([02](./02-csw-generated-powershell.md)) for medium
  fleets, or SCCM / Intune / GPO for anything larger.
- **Production change-controlled environments** where every
  install needs an audit trail. Use a deployment platform — its
  per-host log is your audit record.

---

## See also

- [`02-csw-generated-powershell.md`](./02-csw-generated-powershell.md) — same MSI, with cluster details pre-baked
- [`03-sccm-deployment.md`](./03-sccm-deployment.md) — fleet rollout via SCCM
- [`06-verification.md`](./06-verification.md) — confirm the install
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md) — upgrade procedure
- [`../operations/05-uninstall.md`](../operations/05-uninstall.md) — clean uninstall
