---
title: "CSW Agent — Tanium Deployment Checklist"
subtitle: "One-page field guide for deployment teams"
date: "May 2026"
---

**Repo:** [github.com/chandrapati/CSW-Agent-Installation-Guide](https://github.com/chandrapati/CSW-Agent-Installation-Guide) · **Full runbook:** [`tanium/README.md`](https://github.com/chandrapati/CSW-Agent-Installation-Guide/blob/main/tanium/README.md)

## Critical rule

**Write `user.cfg` with the activation key in the install directory *before* Tanium runs any install command.** Without it, the agent may install but stay *Not Active* / *unauthorized* in the CSW UI.

```ini
ACTIVATION_KEY=<from CSW UI → Manage → Agents → Install Agent>
HTTPS_PROXY=http://proxy.example.com:8080   # optional
```

---

## Pre-flight (CSW admin)

| Step | Done |
|------|:----:|
| Confirm target **tenant**, **scope**, **OS**, and **sensor type** (Visibility vs Enforcement) | ☐ |
| Open **Manage → Agents → Install Agent**; copy **activation key** (treat as secret) | ☐ |
| Download installer bundle or script for the **same** choices | ☐ |
| Confirm outbound **443/TCP** (and on-prem collector/enforcer ports if applicable) | ☐ |
| Configure **EDR/AV exclusions** on endpoints before deploy | ☐ |
| Store activation key in **Tanium package variable** (not plain-text Git) | ☐ |

---

## Package contents (same folder on every endpoint)

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
