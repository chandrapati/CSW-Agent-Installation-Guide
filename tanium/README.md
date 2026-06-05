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

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- Tanium Deploy or Provision licensed and reachable from target endpoints
- Local **root (Linux)** or **Administrator (Windows)** at install time
- The CSW installer artefacts for your cluster, scope, and sensor type:
  - **Linux:** Agent Script Installer (`.sh`) or Agent Image Installer bundle
    (`.rpm`/`.deb` + site files)
  - **Windows:** Agent Image Installer ZIP (`TetrationAgentInstaller.msi` +
    site files) or CSW-generated PowerShell script
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

## Step 1 — Retrieve the activation key from CSW

1. Log into the CSW UI.
2. Navigate to **Manage → Agents → Install Agent** (or **Manage → Workloads →
   Agents → Installer** — wording varies by release).
3. Choose **tenant** (if multi-tenant), **OS**, **sensor type**, and **target
   scope**.
4. Note or copy the **activation key** displayed for that installer context.
   Treat it as a **secret** — same sensitivity as the generated install script.
5. Download the installer bundle or script for the same choices.

If your organisation rotates activation keys, regenerate the key in the UI and
update Tanium package variables **before** the next deployment wave.

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

1. **Tanium Console → Deploy → Software → New Package**
2. **Name:** `Cisco Secure Workload Agent <version> — <scope>`
3. **Package type:** Standard (or use Provision image hook for bare-metal)
4. **Upload** the layout from Step 3, **or** use a two-step package:
   - **Step 1:** Run staging script (writes `user.cfg` from Tanium variable)
   - **Step 2:** Run install wrapper
5. **Package variables:** define `CSW Activation Key` (secret) and optional
   `CSW HTTPS Proxy` — reference them in staging scripts, not in clear text in
   the package body.

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

| Symptom | Likely cause | Fix |
|---|---|---|
| Install succeeds; agent *Not Active* in UI | `user.cfg` missing, empty, or wrong key | Re-run Step 1–2; confirm `ACTIVATION_KEY=` line in deploy directory **before** install |
| `unauthorized` in agent logs | Key rotated or wrong tenant | Regenerate key in CSW UI; update Tanium variable; redeploy |
| MSI / script can't find site files | Package missing `ca.cert`, `site.cfg`, etc. | Ship full Cisco bundle; don't upload MSI alone |
| Tanium reports success but no service | EDR blocked driver / partial MSI | Check verbose MSI log / `journalctl -u csw-agent`; see [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md) |
| Proxy errors | `HTTPS_PROXY` not set in `user.cfg` | Add proxy line; see [`../operations/02-proxy.md`](../operations/02-proxy.md) |

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
