# Tanium — Cisco Secure Workload Agent Deployment

Deploy the CSW host agent at fleet scale using **Tanium Deploy** (software
packages) or **Tanium Provision** (OS provisioning hooks). This runbook covers
Linux and Windows endpoints where your deployment tooling ships the **Cisco
Agent Image Installer bundle** or the **Agent Script Installer** together with
a **`user.cfg`** file.

> **One-page checklist for deployment teams:**
> [`TANIUM-DEPLOYMENT-CHECKLIST.pdf`](./TANIUM-DEPLOYMENT-CHECKLIST.pdf)
> ([`.md` source](./TANIUM-DEPLOYMENT-CHECKLIST.md) ·
> [`.docx`](./TANIUM-DEPLOYMENT-CHECKLIST.docx) · rebuild:
> `./build-checklist-pdf.sh`)

> **Non-negotiable for automated deployments.** Cisco documents that agents
> register using an **activation key** configured in the **user configuration
> file before installation**. For Tanium (and every other orchestrator that
> distributes the installer bundle or script separately from the CSW UI), you
> must **retrieve the activation key, write `user.cfg`, and place it in the
> same directory as the installer** — **before** Tanium executes the install
> command. Skipping this step produces agents that install but fail registration
> with *Not Active* / *unauthorized* in the CSW UI.

> **Linux and Windows are separate CSW downloads — not one combined package.**
> In the CSW UI (*Manage → Agents → Install Agent*), you choose **OS** first.
> Cisco generates a **different installer for Linux than for Windows**. There is
> no single ZIP or script that installs both. Your Tanium team must build **at
> least two Deploy packages** (one Linux, one Windows) unless you are rolling
> out only one OS family.

---

## Linux vs Windows — separate downloads (read this first)

Cisco does **not** ship one universal agent bundle. Each download from the CSW
UI is scoped to the choices you make in the installer wizard. Treat every row in
the table below as a **separate download** and, in Tanium, a **separate software
package** (or package family).

| What you select in CSW UI | What you get | Tanium package |
|---|---|---|
| **OS = Linux** + RHEL/Rocky/Alma (RPM family) | `.rpm` + site files, or Linux `.sh` script | **Linux RPM Tanium package** → target RHEL-family computer group |
| **OS = Linux** + Ubuntu/Debian (DEB family) | `.deb` + site files, or Linux `.sh` script | **Linux DEB Tanium package** → target Debian-family computer group |
| **OS = Linux** + SUSE | SUSE `.rpm` + site files, or Linux `.sh` script | **Linux SUSE Tanium package** (if your fleet includes SLES) |
| **OS = Windows** | `TetrationAgentInstaller.msi` + site files in a ZIP, or Windows `.ps1` script | **Windows Tanium package** → target Windows computer group |

### What this means for your customer

1. **Download twice (minimum)** if you have both Linux and Windows endpoints —
   once with **Linux** selected, once with **Windows** selected. Do not reuse
   the Linux `.rpm` on Windows or the Windows `.msi` on Linux.
2. **Download again per Linux distro family** if you run both RHEL and Ubuntu —
   an `.rpm` built for RHEL 9 will not install on Ubuntu (you need the `.deb`
   generated for that Ubuntu version).
3. **Use separate Tanium computer groups** — e.g. `CSW-Linux-RHEL-Prod` and
   `CSW-Windows-Server-Prod` — each linked to the matching package.
4. **Activation key and `user.cfg`** — generate or copy the key from the **same
   CSW wizard session** where you downloaded the installer for that OS/scope.
   Keys are tied to tenant + scope; Linux and Windows downloads for the same
   scope may show the same key or separate keys depending on your cluster —
   always use the key displayed for **that** download.
5. **Site files are per download too** — `ca.cert`, `site.cfg`, and related
   files ship with each bundle. Do not mix site files from a Windows ZIP into a
   Linux Tanium package (or vice versa).

```
CSW UI — Install Agent
        │
        ├── OS: Linux  ──► Download #1 (e.g. RHEL 9 .rpm + site files)
        │       └── Tanium Package A → Linux endpoints only
        │
        └── OS: Windows ──► Download #2 (.msi ZIP + site files)
                └── Tanium Package B → Windows endpoints only
```

If your fleet is **Linux-only**, you still need **one Tanium package per distro
packaging format** (RPM vs DEB) unless every Linux host shares the same family.

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- Tanium Deploy or Provision licensed and reachable from target endpoints
- Local **root (Linux)** or **Administrator (Windows)** at install time
- The CSW installer artefacts for your cluster, scope, and sensor type —
  **downloaded separately per OS** (see [Linux vs Windows — separate downloads](#linux-vs-windows--separate-downloads-read-this-first)):
  - **Linux only:** Agent Script Installer (`.sh`) or Agent Image Installer
    (`.rpm` *or* `.deb` + site files — match the host's distro)
  - **Windows only:** Agent Image Installer ZIP (`TetrationAgentInstaller.msi` +
    site files) or CSW-generated PowerShell script
  - **Not valid:** one Tanium package containing both `.msi` and `.rpm`/`.deb`
- A secure channel to inject the activation key into Tanium (Tanium **Global
  Variable**, **Package variable**, or secrets store — never hardcode the key
  in a Tanium package definition checked into Git)

---

## Step 0 — Understand the `user.cfg` requirement

Cisco's Agent Image Installer bundle ships these site-related files alongside
the installer (Windows example from
[`../windows/01-msi-silent-install.md`](../windows/01-msi-silent-install.md)):

| File | Purpose |
|---|---|
| `ca.cert` | Cluster CA for TLS (mandatory) |
| `sensor_config` | Deep-visibility sensor config (mandatory) |
| `sensor_type` | Sensor type |
| `site.cfg` | Site / cluster endpoint config (mandatory) |
| **`user.cfg`** | **Activation key + optional HTTPS proxy** — **mandatory for SaaS** and for **non-default tenants on multi-tenant on-prem clusters** |
| `enforcer.cfg` | Enforcement config (enforcement agents only) |

For **automated deployments** (Tanium, SCCM, Ansible image-installer pattern,
cloud-init with a local bundle, etc.), treat `user.cfg` as a **first-class
deliverable**:

1. Download the installer bundle or script from the CSW UI.
2. **Copy the activation key** from the same *Manage → Agents → Install Agent*
   workflow (or from the scope / tenant settings your CSW admin provides).
3. **Write `user.cfg`** with that key **before** packaging for Tanium.
4. Ship **`user.cfg` + all other site files + installer** in one Tanium
   package directory.
5. Only then run the install script or MSI.

> **Agent Script Installer note.** The CSW-generated shell / PowerShell script
> often embeds the activation key. If your Tanium package uses **only** that
> script **and** your CSW admin confirms no external `user.cfg` is required for
> your tenant, you may omit a separate file — but **confirm in your cluster's
> Installer screen** before production rollout. When in doubt, or when Cisco's
> UI ships a `user.cfg` in the bundle, **always pre-stage it**.

---

## Step 1 — Retrieve the activation key and download (per OS)

Repeat this step **once per OS family** you are deploying (Linux and Windows are
**separate** wizard runs and **separate** downloads).

1. Log into the CSW UI.
2. Navigate to **Manage → Agents → Install Agent** (or **Manage → Workloads →
   Agents → Installer** — wording varies by release).
3. Choose **tenant** (if multi-tenant), **OS** (**Linux** *or* **Windows** —
   not both), **distribution/version** (Linux only), **sensor type**, and
   **target scope**.
4. Note or copy the **activation key** displayed for **this** installer context.
   Treat it as a **secret** — same sensitivity as the generated install script.
5. Click **Download** — save the Linux `.rpm`/`.deb`/`.sh` **or** the Windows
   MSI/ZIP/`.ps1`. This download applies **only** to the OS you selected.
6. If you also deploy the other OS, **start a new wizard run**, select the other
   **OS**, and download again.

If your organisation rotates activation keys, regenerate the key in the UI and
update the matching Tanium package variable **for that OS package** before the
next deployment wave.

---

## Step 2 — Create `user.cfg` (before any install command)

Create `user.cfg` in the **same folder** Tanium will extract the package to
(typically a fixed path such as `C:\Program Files\Tanium\Tanium Client\Downloads\...`
on Windows or `/opt/tanium/csw/` on Linux — **pick one path and keep it
consistent**).

### Template

See [`examples/user.cfg.example`](./examples/user.cfg.example). Minimum content:

```ini
ACTIVATION_KEY=<paste-activation-key-from-csw-ui>
```

Optional proxy (when the workload egresses through a forward proxy):

```ini
HTTPS_PROXY=http://proxy.example.com:8080
```

### File permissions

| OS | Recommendation |
|---|---|
| Linux | `chmod 600 user.cfg`; owner `root` |
| Windows | ACL: Administrators + SYSTEM only; remove Users read |

### Staging scripts (for Tanium package steps)

Use these as **early steps** in your Tanium package — they **fail closed** if
`user.cfg` is missing or empty:

- Linux: [`examples/stage-user-cfg.sh`](./examples/stage-user-cfg.sh)
- Windows: [`examples/stage-user-cfg.ps1`](./examples/stage-user-cfg.ps1)

**Tanium pattern — inject key from a variable:**

```bash
# Linux Tanium package step (conceptual)
export CSW_ACTIVATION_KEY='{{Package Variable: CSW Activation Key}}'
/opt/tanium/csw/stage-user-cfg.sh /opt/tanium/csw
```

```powershell
# Windows Tanium package step (conceptual)
$env:CSW_ACTIVATION_KEY = '{{Package Variable: CSW Activation Key}}'
& 'C:\Program Files\Tanium\csw\stage-user-cfg.ps1' -InstallDir 'C:\Program Files\Tanium\csw'
```

Run staging **before** the install script or `msiexec` step — never after.

---

## Step 3 — Build the Tanium package contents

Lay out the package so every file the Cisco installer expects sits **together**:

### Linux (Agent Image Installer bundle)

```
/opt/tanium/csw/                          # or your chosen root
├── user.cfg                              ← pre-staged (Step 2)
├── ca.cert
├── sensor_config
├── site.cfg
├── sensor_type
├── enforcer.cfg                          ← if enforcement
├── tet-sensor-<version>.<distro>.rpm     ← or .deb
└── tanium-linux-install.sh               ← wrapper; see examples/
```

### Linux (Agent Script Installer)

```
/opt/tanium/csw/
├── user.cfg                              ← pre-staged when required
├── ca.cert                               ← if UI shipped site files
├── site.cfg                              ← if applicable
└── install_sensor.sh                     ← from CSW UI
```

### Windows (Agent Image Installer ZIP)

```
C:\Program Files\Tanium\csw\
├── user.cfg                              ← pre-staged (Step 2)
├── ca.cert
├── sensor_config
├── site.cfg
├── sensor_type
├── enforcer.cfg                          ← if enforcement
├── TetrationAgentInstaller.msi
└── tanium-windows-install.ps1            ← wrapper; see examples/
```

**Do not** distribute the MSI alone without the site files and `user.cfg`.

---

## Step 4 — Configure Tanium Deploy

These steps map to Tanium Deploy's package workflow; adapt names to your Tanium
version.

### 4a — Create the software package

Create **one Tanium package per CSW download** (Linux RPM, Linux DEB, Windows
MSI, etc.). Do not combine OS families in a single package.

1. **Tanium Console → Deploy → Software → New Package**
2. **Name:** use OS in the name so operators can tell them apart, e.g.
   `CSW Agent <version> — Linux RHEL9 — <scope>` and
   `CSW Agent <version> — Windows — <scope>`
3. **Package type:** Standard (or use Provision image hook for bare-metal)
4. **Upload** the layout from Step 3 for **that OS only**, **or** use a two-step
   package:
   - **Step 1:** Run staging script (writes `user.cfg` from Tanium variable)
   - **Step 2:** Run install wrapper (`tanium-linux-install.sh` *or*
     `tanium-windows-install.ps1` — not both)
5. **Package variables:** define `CSW Activation Key` (secret) and optional
   `CSW HTTPS Proxy` — reference them in staging scripts, not in clear text in
   the package body. Use the key from the **matching** CSW download.
6. **Target:** deploy each package only to a computer group filtered by OS
   (and, for Linux, by distro family if you split RPM vs DEB).

### 4b — Install command (Linux)

Use the wrapper so install aborts if `user.cfg` is absent:

```bash
sudo /opt/tanium/csw/tanium-linux-install.sh /opt/tanium/csw
```

Wrapper source: [`examples/tanium-linux-install.sh`](./examples/tanium-linux-install.sh)

For a CSW-generated script only (no separate RPM):

```bash
sudo bash /opt/tanium/csw/install_sensor.sh --logfile=/var/log/tetration/tanium-install.log
```

Ensure Step 2 ran first when `user.cfg` is required.

### 4c — Install command (Windows)

Elevated PowerShell:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Program Files\Tanium\csw\tanium-windows-install.ps1" -InstallDir "C:\Program Files\Tanium\csw"
```

Wrapper source: [`examples/tanium-windows-install.ps1`](./examples/tanium-windows-install.ps1)

### 4d — Success criteria

| OS | Tanium success check |
|---|---|
| Linux | Exit code `0` from wrapper **and** `systemctl is-active csw-agent` |
| Windows | Exit code `0` **and** `(Get-Service CswAgent).Status -eq 'Running'` |

Optional **Tanium Sensor** for ongoing compliance:

- Linux: `Service Running Match[csw-agent] equals true`
- Windows: `Service Running Match[CswAgent] equals true`

### 4e — Targeting and rollout

1. Create a **computer group** (OS, datacenter, scope label, etc.).
2. **Deploy → New Deployment** → select package → target group.
3. Roll in **waves** (pilot → production) per
   [`../operations/07-enforcement-rollout.md`](../operations/07-enforcement-rollout.md).
4. Confirm registration in CSW **Manage → Agents → Software Agents** within
   1–2 minutes per host.

---

## Step 5 — Verify registration

- **CSW UI:** host appears *Running* under the scope chosen at key generation.
- **Linux:** [`../linux/08-verification.md`](../linux/08-verification.md)
- **Windows:** [`../windows/06-verification.md`](../windows/06-verification.md)

---

## Troubleshooting

Start with the symptom. Tanium-specific issues are listed first; then
Linux- and Windows-specific diagnostics. Full cross-platform flowcharts:
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

### Tanium package / deployment issues (all OS)

| Symptom | Likely cause | Fix |
|---|---|---|
| Package step 1 succeeds, step 2 fails immediately | Install ran before `user.cfg` was staged | Re-order package steps: **stage key → deploy bundle → install** |
| `CSW_ACTIVATION_KEY is not set` from staging script | Tanium variable not bound to package | Define secret package variable; map to `CSW_ACTIVATION_KEY` env var |
| Tanium reports success but CSW UI shows *Not Active* | Empty/wrong `ACTIVATION_KEY` in `user.cfg` | Confirm `grep ACTIVATION_KEY` on endpoint **before** install; regenerate key in CSW UI |
| Package succeeds on pilot, fails at scale | Mixed OS/arch in one package | **Separate Tanium packages** per CSW download: Linux RPM, Linux DEB, Windows — never combined |
| `OS not supported` / wrong package type on Linux | Windows MSI or wrong `.rpm`/`.deb` in Linux package | Re-download from CSW UI with **Linux** + correct distro; rebuild Linux-only package |
| MSI/script errors on Windows | Linux `.sh` or `.rpm` deployed to Windows hosts | Re-download with **Windows** selected; Windows-only Tanium package |
| Intermittent failures across fleet | Tanium client check-in / action timeout | Increase package timeout; roll in smaller computer groups |
| Install files missing on endpoint | Package extract path differs from script `-InstallDir` | Use one fixed path (`/opt/tanium/csw/` or `C:\Program Files\Tanium\csw\`) in all steps |

---

### Linux — troubleshooting

#### Collect evidence first

```bash
# Service state
sudo systemctl status csw-agent
sudo journalctl -u csw-agent -n 200 --no-pager

# Agent logs (release-dependent path)
sudo ls -la /var/log/tetration/ 2>/dev/null
sudo tail -100 /var/log/tetration/*.log 2>/dev/null

# Confirm user.cfg was present before install
sudo cat /opt/tanium/csw/user.cfg   # adapt path
grep -E '^ACTIVATION_KEY=' /opt/tanium/csw/user.cfg

# Network egress (on-prem example — adapt IPs from CSW UI)
nc -zv <CFG-SERVER> 443
nc -zv <COLLECTOR> 5640

# SELinux (if enforcing)
sudo ausearch -m avc -ts recent | grep -iE 'csw|tet'
```

#### Linux symptom table

| Symptom | Likely cause | Fix |
|---|---|---|
| Wrapper exits: `Missing user.cfg` | Staging step skipped or wrong directory | Run `stage-user-cfg.sh` first; confirm path matches install wrapper |
| Wrapper exits: `ACTIVATION_KEY is empty` | Tanium variable blank or staging failed | Test staging script manually with exported key |
| `download failed: cannot reach <cluster>` | Egress/firewall blocked | Open ports per [`../operations/01-network-prereq.md`](../operations/01-network-prereq.md); or pre-download package |
| `tls handshake failed: x509: certificate signed by unknown authority` | Wrong/missing `ca.cert` | Re-ship full Cisco bundle from **this** cluster |
| `tls handshake failed: certificate has expired or is not yet valid` | Clock skew | `chronyc tracking` / `timedatectl`; fix NTP |
| `csw-agent` failed — kernel module compile | Missing `kernel-devel` for running kernel | `dnf install kernel-devel-$(uname -r)` (or apt equivalent); reinstall |
| Service active but UI *Not Active* | Key rejected or proxy missing | Verify `user.cfg`; add `HTTPS_PROXY`; regenerate key |
| `OS not supported` in installer log | Wrong `.rpm`/`.deb` for distro | Re-download from CSW UI for correct OS family |
| Tanium install log shows permission denied | Script not run as root | Tanium package must use `sudo` / root context for install step |
| Hangs at package signature validation | Time skew or corrupt download | Sync NTP; re-upload package to Tanium |

Deeper verification: [`../linux/08-verification.md`](../linux/08-verification.md)

---

### Windows — troubleshooting

#### Collect evidence first

```powershell
# Service state
Get-Service -Name CswAgent
Get-WinEvent -LogName Application -MaxEvents 100 |
  Where-Object { $_.Message -like '*Csw*' -or $_.Message -like '*Secure Workload*' } |
  Format-Table TimeCreated, LevelDisplayName, Message -AutoSize

# MSI verbose log (path from tanium-windows-install.ps1 or package)
Get-Content "$env:TEMP\csw-agent-tanium-install.log" -Tail 80

# Confirm user.cfg before reinstall
Get-Content 'C:\Program Files\Tanium\csw\user.cfg'

# Network
Test-NetConnection <cluster-fqdn> -Port 443
```

Search the MSI log for `Return value 3` — the line above it is usually the root cause.

#### Windows symptom table

| Symptom | Likely cause | Fix |
|---|---|---|
| Wrapper throws: `Missing user.cfg` | Staging step skipped | Run `stage-user-cfg.ps1` as **first** package step |
| Wrapper throws: `ACTIVATION_KEY is empty` | Tanium secret variable not set | Bind `CSW Activation Key` package variable |
| `msiexec` exit `1603` | Generic MSI failure | Read verbose log; common sub-cause is EDR block |
| `Error 1722` in MSI log | Custom action failed (often Defender) | Add Cisco exclusions per [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md) |
| Service missing after "success" | Partial MSI / driver not loaded | Re-extract full ZIP; confirm `ca.cert`, `site.cfg`, `sensor_config` present |
| `tls handshake failed: x509 unknown authority` | Site files not from this cluster | Re-download Cisco package; do not hand-craft `ca.cert` |
| Service running; UI *Not Active* | Wrong/missing activation key | Pre-stage `user.cfg` **before** MSI; regenerate key if rotated |
| `Test-NetConnection` fails on 443 | Firewall / proxy | Open egress; add `HTTPS_PROXY` to `user.cfg` |
| `kernel filter driver failed to load` | Secure Boot / signing policy | Confirm Cisco-signed driver allowed by policy |
| Tanium success but no install log | Wrong working directory | Pass full path to `-InstallDir`; run PowerShell elevated |
| `unauthorized` after registration attempt | Key rotated or wrong tenant | Regenerate MSI bundle + update Tanium variable |

Deeper verification: [`../windows/06-verification.md`](../windows/06-verification.md)

---

## Automated deployment checklist

Use this for Tanium **and** any other orchestrator (Ansible, SCCM, Intune,
cloud-init):

- [ ] Activation key retrieved from CSW UI for the correct **tenant + scope**
- [ ] **`user.cfg` written with `ACTIVATION_KEY`** (and proxy if needed)
- [ ] **`user.cfg` deployed to the install directory before the install command**
- [ ] Full site file set (`ca.cert`, `site.cfg`, …) present alongside installer
- [ ] Activation key stored in orchestrator secrets — not in plain-text Git
- [ ] Install wrapper validates `user.cfg` exists (fail closed)
- [ ] Post-install: service running + CSW UI shows *Running*

---

## See also

- [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md) — activation key + user config file
- [`../windows/01-msi-silent-install.md`](../windows/01-msi-silent-install.md) — Windows site files + `user.cfg`
- [`../linux/02-csw-generated-script.md`](../linux/02-csw-generated-script.md) — Linux Agent Script Installer
- [`../windows/03-sccm-deployment.md`](../windows/03-sccm-deployment.md) — parallel Windows enterprise pattern
- [`../linux/04-ansible.md`](../linux/04-ansible.md) — Linux fleet automation
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)
