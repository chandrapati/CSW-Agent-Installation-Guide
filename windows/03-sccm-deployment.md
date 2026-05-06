# Windows — Microsoft Configuration Manager (SCCM / MECM)

The standard enterprise pattern for Windows fleets. Package the
CSW MSI as an Application in Configuration Manager, deploy it as
a Required Deployment to the target collection, and back it with
a Compliance Baseline that watches the `CswAgent` service. This
gives you inventory tracking, retry logic, audit log, and
compliance reporting out of the box.

> *Microsoft Endpoint Configuration Manager* (MECM), formerly
> *System Center Configuration Manager* (SCCM). The terms are
> interchangeable in current literature; this doc uses "SCCM" for
> brevity.

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- A working SCCM site with Distribution Points (DPs) reachable
  from the target collection
- The CSW MSI (`TetrationAgentInstaller-3.x.y.z-x64.msi`)
  downloaded from the CSW UI for your target scope and sensor type
- An SCCM service account with rights to create Applications,
  Deployments, and Compliance Baselines
- A target collection of devices (could be all servers, an OU,
  a custom query collection, etc.)

---

## Step 1 — Stage the MSI on a content source

Place the MSI in a UNC-accessible source location that SCCM can
read:

```
\\sccm-content.example.com\sources$\Apps\CiscoSecureWorkload\3.x.y.z\
    └── TetrationAgentInstaller-3.x.y.z-x64.msi
    └── (optional) install_logger.ps1   ← for verbose log capture
    └── (optional) ca.pem               ← on-prem cluster CA chain
```

**Why a versioned subfolder.** When you publish the next CSW
release, place the new MSI under `3.x.y+1.z\` and create a *new*
SCCM Application. Don't update the same Application — Configuration
Manager handles in-place upgrades poorly when the MSI ProductCode
changes (it does, between versions).

---

## Step 2 — Create the SCCM Application

In the Configuration Manager console:

1. *Software Library* → *Application Management* → *Applications*
2. **Create Application** → "Automatically detect information from
   installation files"
3. Source path: `\\sccm-content.example.com\sources$\Apps\CiscoSecureWorkload\3.x.y.z\TetrationAgentInstaller-3.x.y.z-x64.msi`
4. The wizard auto-fills:
   - Application name (edit to: *Cisco Secure Workload Sensor 3.x.y.z*)
   - Software version (`3.x.y.z`)
   - Detection method (auto-set to MSI ProductCode — keep)
   - Install command (auto-set; we'll override)
5. **Override the install command** to add `/quiet /norestart` and
   optional verbose logging:

```text
msiexec /i "TetrationAgentInstaller-3.x.y.z-x64.msi" /quiet /norestart /L*v "%TEMP%\tetsensor-install.log"
```

6. **Set the install behaviour** to *Install for system*.
7. **Set the user experience** to *Hidden*; *Whether or not a
   user is logged on*; *Determine behavior based on return codes*.
8. Save the Application.

---

## Step 3 — Distribute content to DPs

Right-click the Application → *Distribute Content* → choose your
Distribution Point Group → finish the wizard. Wait for content to
replicate (monitor via *Monitoring → Distribution Status*).

---

## Step 4 — Create the Deployment

1. Right-click the Application → *Deploy*
2. **Collection**: select your target collection (e.g., *All
   Windows Servers — Wave 1*)
3. **Deployment settings**:
   - Action: *Install*
   - Purpose: *Required* (this is the key — required deployments
     install whether or not a user is logged on, retry on
     failure, and report compliance)
4. **Scheduling**:
   - Available time: now
   - Deadline: *as soon as possible* for wave deployments, or a
     specific maintenance window
5. **User experience**:
   - Suppress notifications (server-class hosts; users won't see
     anything)
   - Allow restart outside maintenance window: typically *off* —
     CSW agent doesn't require a reboot
6. **Distribution points**: leave default (uses the Distribution
   Point Group from Step 3)
7. **Summary** → finish

The deployment evaluates on the next client check-in cycle
(typically every 60 minutes; you can force with `Invoke-WMIMethod
-Namespace 'root\ccm' -Class SMS_Client -Name TriggerSchedule
-ArgumentList '{00000000-0000-0000-0000-000000000022}'` on a
target).

---

## Step 5 — Create a Compliance Baseline (verification)

A Compliance Baseline turns *"is the agent installed and running"*
into a tracked metric per device.

1. *Assets and Compliance → Compliance Settings → Configuration
   Items* → **Create Configuration Item**
2. Name: *Cisco Secure Workload Sensor — Service Running*
3. Settings:
   - Setting type: *Script*
   - Data type: *String*
   - Discovery script (PowerShell):

```powershell
$svc = Get-Service -Name CswAgent -ErrorAction SilentlyContinue
if ($null -eq $svc) {
    Write-Output "NotInstalled"
} elseif ($svc.Status -eq 'Running') {
    Write-Output "Compliant"
} else {
    Write-Output "NotRunning"
}
```

4. Compliance rule: value equals `Compliant` (Severity:
   *Critical*)
5. Optional: remediation script that does
   `Start-Service -Name CswAgent` (be cautious with auto-remediate
   on critical infra; many orgs prefer alerting + ticket over
   silent remediation)

Create a **Configuration Baseline** that includes this CI, and
deploy the baseline to the same collection. Now SCCM tracks per-
device compliance and you have a single dashboard view of agent
health across the fleet.

---

## Step 6 — Wave-based rollout

Standard SCCM pattern for safe production rollout:

| Wave | Collection | Trigger |
|---|---|---|
| Wave 0 — lab | *Cisco Secure Workload — Lab* (10 hosts) | Required, immediate |
| Wave 1 — stage | *Cisco Secure Workload — Stage* (50 hosts) | Required, after Wave 0 validation |
| Wave 2 — prod canary | *Cisco Secure Workload — Prod Canary* (10 prod hosts) | Required, after Wave 1 validation |
| Wave 3 — prod batches | *Cisco Secure Workload — Prod Batch N* (~10 % of prod per batch) | Required, on weekly cycle |

Move hosts between collections as waves progress. The same
Application is deployed to each — only the collection
membership changes.

---

## Step 7 — Day-2 patching cadence (CSW agent upgrades)

When CSW publishes a new agent release:

1. Stage the new MSI in a new versioned source folder
2. Create a **new** Application *Cisco Secure Workload Sensor
   3.x.y+1.z*
3. Add a **Supersedence** rule: the new Application supersedes
   the old, with *Uninstall the superseded application* set per
   your org's preference (in-place vs. uninstall-then-install)
4. Deploy the new Application to the same collections in waves

The Compliance Baseline from Step 5 keeps watching the service —
its check is version-agnostic, so it continues to report
correctly through upgrades.

---

## Activation key handling

The CSW MSI bakes the activation key in, scoped to the *Manage →
Agents* generation moment. To use one MSI across multiple scopes:

- **Option A — one MSI per scope.** Generate separate MSIs in the
  CSW UI per scope; create one SCCM Application per scope; deploy
  each to its own collection. Cleanest separation.
- **Option B — one MSI for "default" scope, then move workloads
  in CSW UI.** Use a single MSI/Application; move workloads to
  the right scope post-registration via CSW labels. Requires a
  reliable label-mapping process; less SCCM overhead.

Most enterprises pick Option A for production-tier scopes where
the audit trail of "which devices got which scope's MSI" is
valuable.

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Application reports "Past due — will be installed" but never installs | Client check-in not happening | Run `ccmexec` triggers manually; confirm SCCM client is healthy on the target |
| Install reports success but service isn't running | MSI installed but `CswAgent` service failed to start | Check `%TEMP%\tetsensor-install.log` per Step 2; check Application event log; check CA / activation key |
| Compliance Baseline reports `NotInstalled` after install reports success | Detection method mismatch (often after MSI ProductCode change) | Update the Application's detection method to match the new ProductCode |
| Deployment fails with `0x87D00324` (application not detected) | Detection method too strict (e.g., looking for old version) | Re-run *Create Application* wizard with the new MSI to refresh the auto-detection |
| Defender flags the kernel filter driver | Driver not in default Defender allow-list | Pre-stage Cisco's published exception per your Defender / EDR product |

Full troubleshooting in
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## When this is the right method

- **Windows fleets already managed by SCCM / MECM.** Drop into
  the existing rhythm.
- **Regulated environments** that need per-device install audit
  trail and compliance reporting (PCI, HIPAA, SOX, etc.).
- **Mixed server-class fleets** spanning multiple OUs and AD
  sites where SCCM is the single source of truth.

## When this is NOT the right method

- **Cloud-managed Windows estate** (Azure AD-joined, Intune-
  managed). Use Intune ([04](./04-intune-deployment.md)) — it's
  the better fit.
- **Greenfield without an existing SCCM investment.** Setting up
  SCCM just for CSW is overkill — use Intune or PowerShell
  remoting.

---

## See also

- [`01-msi-silent-install.md`](./01-msi-silent-install.md) — what the MSI does on a single host
- [`04-intune-deployment.md`](./04-intune-deployment.md) — cloud-managed alternative
- [`05-group-policy.md`](./05-group-policy.md) — fallback when SCCM isn't available
- [`06-verification.md`](./06-verification.md)
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md) — supersedence-driven upgrades
