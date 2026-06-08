---
title: "CSW Agent — Tanium Deployment Checklist"
subtitle: "One-page field guide for deployment teams"
date: "May 2026"
---

**Repo:** [github.com/chandrapati/CSW-Agent-Installation-Guide](https://github.com/chandrapati/CSW-Agent-Installation-Guide) · **Full runbook:** [`tanium/README.md`](https://github.com/chandrapati/CSW-Agent-Installation-Guide/blob/main/tanium/README.md)

## Critical rules

**1. Linux and Windows are separate CSW downloads.** In *Manage → Agents → Install
Agent*, choose **OS = Linux** and download (`.rpm`/`.deb`/`.sh` + site files),
then run the wizard again with **OS = Windows** and download (`.msi` ZIP + site
files). Build **separate Tanium packages** — do not put Windows and Linux
installers in one package.

**2. Pre-stage `user.cfg` before install.** Write the activation key in the
install directory *before* Tanium runs any install command. Without it, the
agent may install but stay *Not Active* / *unauthorized* in the CSW UI.

```ini
ACTIVATION_KEY=<from CSW UI → Manage → Agents → Install Agent>
HTTPS_PROXY=http://proxy.example.com:8080   # optional
```

---

## Pre-flight (CSW admin)

Complete the block below **once per OS** (Linux download, then Windows download
if both are in scope).

| Step | Done |
|------|:----:|
| Confirm target **tenant**, **scope**, **OS**, and **sensor type** (Visibility vs Enforcement) | ☐ |
| **Linux:** wizard → OS **Linux** → pick **distro/version** → copy **activation key** → **Download** (`.rpm` or `.deb` or `.sh` + site files) | ☐ |
| **Windows:** new wizard run → OS **Windows** → copy **activation key** → **Download** (MSI ZIP + site files) | ☐ |
| Confirm outbound **443/TCP** (and on-prem collector/enforcer ports if applicable) | ☐ |
| Configure **EDR/AV exclusions** on endpoints before deploy | ☐ |
| Create **separate Tanium packages** (Linux vs Windows; split RPM vs DEB if needed) | ☐ |
| Store each OS's activation key in **that package's** Tanium variable (not plain-text Git) | ☐ |

---

## Tanium packages (one per CSW download)

| Tanium package | CSW download | Target group |
|----------------|--------------|--------------|
| CSW — Linux RHEL/Rocky (RPM) | OS Linux + RPM family | Linux RPM hosts only |
| CSW — Linux Ubuntu/Debian (DEB) | OS Linux + DEB family | Linux DEB hosts only |
| CSW — Windows | OS Windows + MSI ZIP | Windows hosts only |

---

## Package contents (same folder on every endpoint — per OS package)

| File | Required |
|------|:--------:|
| **`user.cfg`** (with `ACTIVATION_KEY` pre-staged) | **Yes** |
| `ca.cert` | Yes |
| `site.cfg` | Yes |
| `sensor_config` | Yes |
| `sensor_type` | Yes |
| `enforcer.cfg` | If enforcement |
| `TetrationAgentInstaller.msi` (Windows) or `.rpm`/`.deb`/`.sh` (Linux) | Yes |

**Suggested paths:** Linux `/opt/tanium/csw/` · Windows `C:\Program Files\Tanium\csw\`

---

## Tanium Deploy package steps (order matters)

| # | Package step | Done |
|---|--------------|:----:|
| 1 | **Stage `user.cfg`** — run `stage-user-cfg` script with `CSW_ACTIVATION_KEY` from Tanium variable | ☐ |
| 2 | Deploy full Cisco bundle (site files + installer) to install directory | ☐ |
| 3 | **Install** — Linux: `tanium-linux-install.sh` · Windows: `tanium-windows-install.ps1` | ☐ |
| 4 | Success criteria: exit code **0** + service **Running** (`csw-agent` / `CswAgent`) | ☐ |
| 5 | Pilot wave → production waves; confirm CSW UI shows host **Running** within 1–2 min | ☐ |

---

## Post-deploy verification

| Check | Linux | Windows |
|-------|-------|---------|
| Service running | `systemctl is-active csw-agent` | `Get-Service CswAgent` |
| CSW UI | *Manage → Agents → Software Agents* — status **Running**, correct scope | Same |

---

## If something fails

### All platforms (Tanium)

| Symptom | First action |
|---------|--------------|
| *Not Active* / *unauthorized* | Confirm `user.cfg` with valid `ACTIVATION_KEY` existed **before** install step ran |
| Package step order wrong | Rebuild package: **(1) stage user.cfg → (2) deploy bundle → (3) install** |
| Key in Tanium variable empty | Fix secret variable binding; pilot on one host before fleet |
| Linux hosts get Windows MSI (or vice versa) | Wrong package targeted | Separate CSW downloads → separate Tanium packages → OS-filtered computer groups |
| `OS not supported` on Linux | `.deb` sent to RHEL or `.rpm` to Ubuntu | Download correct family from CSW UI; match package to distro |

### Linux

| Symptom | First action |
|---------|--------------|
| Install fails immediately | `journalctl -u csw-agent -n 50`; confirm `user.cfg` at `/opt/tanium/csw/` |
| TLS / cert errors | Re-ship `ca.cert` + full bundle from CSW UI |
| Service won't start | Check kernel-devel match: `uname -r`; check SELinux AVC denials |
| Network timeout | `nc -zv <cluster> 443`; open firewall per network prereq doc |

### Windows

| Symptom | First action |
|---------|--------------|
| MSI failure | Open `%TEMP%\csw-agent-tanium-install.log`; search `Return value 3` |
| Service not running | `Get-Service CswAgent`; check Application event log |
| EDR block (1722 / 1603) | Add Defender exclusions before redeploy |
| Network | `Test-NetConnection <cluster> -Port 443`; add `HTTPS_PROXY` to `user.cfg` if proxied |

**Full troubleshooting:** [`tanium/README.md`](https://github.com/chandrapati/CSW-Agent-Installation-Guide/blob/main/tanium/README.md#troubleshooting) · [`operations/06-troubleshooting.md`](https://github.com/chandrapati/CSW-Agent-Installation-Guide/blob/main/operations/06-troubleshooting.md)

---

*Draft v1 — cross-check against the Cisco Secure Workload User Guide for your release before production use.*
