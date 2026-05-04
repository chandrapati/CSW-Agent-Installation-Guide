# Windows — CSW-Generated PowerShell Installer

The Windows analogue of the Linux CSW-generated shell script. The
CSW cluster builds a self-contained PowerShell installer for each
(sensor type, scope) combination. Run it on the workload as
Administrator and it handles **everything**: MSI download, TLS
trust setup, activation key, scope assignment, service start,
registration.

> The script is **per-tenant and per-cluster**. The activation key
> baked into it is tied to the CSW cluster and chosen scope. Do
> not share the script across tenants or clusters; regenerate it
> for each.

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- Local administrator on the workload
- PowerShell 5.1+ (default on every supported Windows release)
- Either: outbound HTTPS from the workload to the CSW cluster
  (the script downloads its MSI payload from the cluster);
  **or** the script downloaded once and copied to the workload
  via your file-transfer mechanism

---

## Step 1 — Generate the script in the CSW UI

1. Log into the CSW UI
2. Navigate to *Manage → Agents → Install Agent*
3. Choose **Windows** as the OS
4. Choose the **sensor type** (Deep Visibility or Enforcement)
5. Choose the **target scope** — the workload will land in this
   scope on first registration
6. Click *Download Installer Script* (the file is a `.ps1`,
   typically named `tetration_installer_<scope>_windows.ps1` or
   similar)

The downloaded script bundles:

- The activation key for your cluster
- The cluster collector VIP (or SaaS hostname)
- The cluster CA chain (if on-prem with private CA)
- The download URL of the MSI payload
- Scope and registration parameters

You don't need to edit the script — the cluster has configured it
for the choices you made.

---

## Step 2 — Transfer to the workload

Two patterns:

### Pattern A — workload has direct egress to the cluster

Most common. Copy only the script to the host and let it download
the MSI payload itself.

```powershell
# From a jump host that can reach the workload
$session = New-PSSession -ComputerName workload.example.com
Copy-Item -ToSession $session -Path .\install_sensor.ps1 -Destination C:\temp\
Remove-PSSession $session
```

Or via SMB share / RDP file copy / your usual method.

### Pattern B — script downloaded once, distributed via your channel

If the workload doesn't have direct egress, you can pre-download
the MSI alongside the script and ship them together. Some script
versions accept a flag to read the MSI from a local path; check
`./install_sensor.ps1 -Help` for your release.

---

## Step 3 — Run the script (elevated)

Open PowerShell **as Administrator** and run:

```powershell
# Allow execution for this session (the script may be unsigned;
# adjust to your org's signing policy)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Run
& C:\temp\install_sensor.ps1
```

The script:

1. Checks the OS / build against its supported list
2. (Optional) prompts for proxy details if it can't reach the
   cluster directly
3. Downloads the MSI over HTTPS from the cluster
4. Validates the MSI signature
5. Deposits the cluster CA chain (on-prem) at the agent conf
   directory
6. Runs `msiexec /i <msi> /quiet /norestart`
7. Writes activation details to the agent registry / config
8. Starts the `TetSensor` service (and any related services)
9. Registers with the cluster

Expected end-of-run output (paraphrased):

```
[INFO] Sensor installation complete
[INFO] Service TetSensor started
[INFO] Sensor registered with cluster <cluster>
[INFO] Workload UUID: <uuid>
```

Common script flags (varies by release; always check `-Help`
first):

| Flag | Purpose |
|---|---|
| `-Proxy <url>` | Send all agent traffic through an HTTP proxy |
| `-ProxyUser <user>` / `-ProxyPassword <pwd>` | Proxy auth |
| `-NoDownload` | Don't download the MSI; read it from a local path |
| `-MsiPath <path>` | Path to a pre-downloaded MSI |
| `-Silent` | Non-interactive; for use in pipelines |
| `-LogPath <path>` | Specify a verbose install log path |
| `-Help` | Show all flags for your script's release |

---

## Step 4 — Confirm registration in the CSW UI

In CSW *Manage → Agents → Software Agents*, the new host should
appear within 1–2 minutes of script completion, with status
*Running* and the scope you selected at script-generation time.

For deeper verification, see [`06-verification.md`](./06-verification.md).

---

## Pushing the script to many hosts at once

The script is fundamentally a per-host operation, but you can
parallelise the per-host invocation. Common patterns:

### PowerShell remoting (`Invoke-Command -AsJob`)

```powershell
$hosts = Get-Content .\inventory.txt
$cred = Get-Credential   # account with admin on the targets

# Push the script to each host
foreach ($h in $hosts) {
    $sess = New-PSSession -ComputerName $h -Credential $cred
    Copy-Item -ToSession $sess -Path .\install_sensor.ps1 -Destination C:\temp\
    Remove-PSSession $sess
}

# Execute in parallel (up to N concurrent jobs)
$jobs = $hosts | ForEach-Object {
    $h = $_
    Invoke-Command -ComputerName $h -Credential $cred -ScriptBlock {
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        & C:\temp\install_sensor.ps1 -Silent
    } -AsJob -JobName "csw-install-$h"
}

# Wait + collect
$jobs | Wait-Job | Receive-Job
```

### From a CI/CD job using WinRM / SSH on Windows

If your CI/CD runner can WinRM (via Ansible's `winrm` connection
plugin or PowerShell remoting), wrap the same commands in a job
step.

For anything beyond a few dozen hosts, **stop using the script in
a loop and switch to SCCM** ([03](./03-sccm-deployment.md)) or
**Intune** ([04](./04-intune-deployment.md)) — they give you
inventory tracking, retry logic, compliance baselines, and a
proper audit log.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Script blocked by execution policy | Org policy enforces signed scripts | Sign the script with your code-signing cert; or run with `-ExecutionPolicy Bypass` for the session (subject to org policy) |
| `Invoke-WebRequest: cannot find URL` during download | Workload can't reach the cluster on 443/TCP | `Test-NetConnection <cluster> -Port 443`; open the firewall port; or use `-NoDownload -MsiPath` |
| Script reports `OS not supported` | OS / build not on the matrix for this CSW release | Check the Compatibility Matrix |
| `TetSensor` started but registration is *Not Active* in UI | Activation key rejected | Regenerate the script in the UI; rerun |
| Hangs at "validating MSI signature" | Time skew | Confirm `w32time` is in sync (`w32tm /query /status`) |
| Defender / EDR quarantines the agent during install | EDR sees a previously unknown driver | Pre-stage Cisco's published allow-list / exception per your EDR product |

Full troubleshooting in
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## When this is the right method

- **First-month POV / pilot Windows deployments** where the team
  wants to get the agent on hosts quickly without bringing SCCM
  / Intune into scope.
- **Small to medium Windows fleets** (up to a few hundred hosts)
  with PowerShell remoting available but no full deployment
  platform.
- **One-off remediation** for hosts that drifted out of compliance
  with the central pipeline.

## When this is NOT the right method

- **Fleets > a few hundred hosts.** Move to SCCM / Intune — they
  handle inventory, retries, compliance baselines, and upgrade
  cycles much better.
- **Cloud-managed Windows estates.** Use Intune — it's designed
  for the use case.

---

## See also

- [`01-msi-silent-install.md`](./01-msi-silent-install.md) — the manual baseline
- [`03-sccm-deployment.md`](./03-sccm-deployment.md) — SCCM rollout
- [`04-intune-deployment.md`](./04-intune-deployment.md) — Intune rollout
- [`06-verification.md`](./06-verification.md)
- [`../operations/02-proxy.md`](../operations/02-proxy.md) — proxy configuration
