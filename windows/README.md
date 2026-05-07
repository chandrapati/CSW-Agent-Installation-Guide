# Windows — Installation Methods

Pick the runbook that matches your environment. All methods
produce the same end-state: the CSW Windows agent installed
running as the **`CswAgent`** Windows service (display name
"Cisco Secure Workload Deep Visibility"; the underlying agent
process is `CswEngine.exe`, with `TetEnfC.exe` engaged on
enforcement-enabled hosts), and registered against the CSW
cluster.

> **Authoritative source.** Service / process / VDI / Npcap
> claims on this page come directly from Cisco's
> [Install Windows Agents for Deep Visibility and Enforcement](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/install-windows-agents-for-deep-visibility-and-enforcement.html)
> chapter and the
> [Post Installation Tasks and Details for Software Agents](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/post-installation-tasks-and-details-for-software-agents.html)
> chapter (Security Exclusions Table 3). If your release
> differs, trust the *Manage → Workloads → Agents → Installer*
> screen in your cluster.

> **Naming note.** Cisco Secure Workload 4.0 documents the
> Windows service as **`CswAgent`**. This guide targets CSW 4.0,
> so examples should use `CswAgent`. If you are maintaining an
> older Tetration-era deployment whose service is named
> `TetSensor`, use that release's Cisco guide and adapt the
> examples intentionally; do not treat older names as valid CSW
> 4.0 defaults.

> **Before any of these methods**, confirm
> [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
> is satisfied. Most install failures trace back to a
> prerequisite gap, not the method itself.

> **For VDI / VM-template / golden-image deployments — there
> *is* a Cisco-supported path.** Cisco's *Install Windows
> Agent in a VDI Instance or VM Template* section documents
> exact MSI / PowerShell flags that prevent the build VM from
> registering with the cluster, then activate cleanly when
> a clone boots. See the next section.

---

## VDI / VM template / golden image — Cisco's documented flow

Per Cisco's
[Install Windows Agent using the Agent Image Installer Method](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/install-windows-agents-for-deep-visibility-and-enforcement.html),
the supported VDI / VM template flow is:

| Installer | Flag | What it does |
|---|---|---|
| MSI (`msiexec`) | `nostart=yes` | Installs the agent but does **not** start the `CswAgent` service. On VDI / VM instances created from the resulting golden image with a different host name, the service starts automatically. |
| PowerShell installer | `-goldenImage` | Equivalent for the PowerShell-script-driven install. |

Per Cisco: *"Pass this parameter, when installing the agent
using a golden image in a VDI environment or VM template, to
prevent agent service — CswAgent from starting automatically.
On VDI/VM instances created using the golden image and with a
different host name, these services, as expected, start
automatically."*

> **Earlier wording in this guide claimed there is no Windows
> equivalent of Linux's `--golden-image` flag. That was wrong**:
> the equivalents are `nostart=yes` (MSI) and `-goldenImage`
> (PowerShell). They are first-class supported.

**Capture driver context.** Cisco's chapter calls out that:

- **Windows Server 2008 R2** uses **Npcap** for flow capture
  (Cisco ships and supports a specific Npcap version with the
  installer).
- **Modern Windows Server releases** use the in-box
  `ndiscap.sys` (an NDIS LWF driver) — Npcap is **not**
  involved on modern Windows.

The earlier framing in this guide that suggested every Windows
host runs Npcap was incorrect. **Only Windows 2008 R2 and
pre-3.8 agents bind to Npcap; modern installs do not.**

---

## Methods in this folder

| # | Method | Best for | Doc |
|---|---|---|---|
| 01 | Manual MSI silent install | One-off lab installs | [01-msi-silent-install.md](./01-msi-silent-install.md) |
| 02 | CSW-generated PowerShell script | Small to medium fleets without a deployment platform | [02-csw-generated-powershell.md](./02-csw-generated-powershell.md) |
| 03 | Microsoft Configuration Manager (SCCM / MECM) | Standard enterprise pattern for on-prem Windows fleets | [03-sccm-deployment.md](./03-sccm-deployment.md) |
| 04 | Microsoft Intune | Cloud-managed Windows fleets | [04-intune-deployment.md](./04-intune-deployment.md) |
| 05 | Group Policy (GPO) startup script | Domain-joined fallback when SCCM / Intune aren't available | [05-group-policy.md](./05-group-policy.md) |
| 06 | Verification | Confirming the install actually worked | [06-verification.md](./06-verification.md) |

> **Cisco-documented** vs. **community pattern** breakdown:
> Methods 01 and 02 follow Cisco's *Install Windows Agent*
> sections directly. Methods 03–05 are practitioner / customer
> patterns built on top of Method 01 / 02 — Cisco doesn't
> publish vendor-specific SCCM / Intune / GPO playbooks but
> these patterns are widely used in production.

---

## OS support snapshot

The Windows agent supports current Windows Server releases.
Always cross-check the
[Compatibility Matrix](https://www.cisco.com/c/m/en_us/products/security/secure-workload-compatibility-matrix.html)
in the CSW documentation portal for your specific CSW release.

| Family | Commonly supported versions |
|---|---|
| Windows Server | 2012 R2 · 2016 · 2019 · 2022 · 2025 |
| Windows Server 2008 R2 | Supported on older agents — Npcap-based flow capture, with a documented clock-drift caveat (Go 1.15 / `tet-main.exe` on this OS) |
| Windows Client (when allowed by the platform team) | 10 · 11 |

For laptops / desktops in a user-endpoint role, **a CSW agent
is not required** when the endpoint runs **Cisco AnyConnect /
Secure Client with NVM** or is registered with **Cisco ISE**.
See [`../docs/05-anyconnect-ise-alternatives.md`](../docs/05-anyconnect-ise-alternatives.md).

---

## Agent flavours on Windows

Per Cisco's *Install Windows Agents* section, the modern
Windows agent ships **one** package that contains both
visibility and enforcement capability. Whether it actually
enforces is determined by the cluster-side **Agent Config
Profile**, not by which package was installed.

| Mode | Service | Service binary (Cisco doc Table 3) | Provides |
|---|---|---|---|
| Deep Visibility (default) | `CswAgent` | `CswEngine.exe` | Flow + process + software inventory + CVE lookup |
| Enforcement | `CswAgent` (same service; enforcement engaged via cluster Agent Config Profile) | `CswEngine.exe` + `TetEnfC.exe` + Windows Filtering Platform (WFP) integration | Deep Visibility + WFP-based workload firewall enforcement |

**Display name** (from `sc qc cswagent`): *Cisco Secure
Workload Deep Visibility*.

The CSW *Manage → Workloads → Agents → Installer* UI shows the
exact MSI file name for your cluster. The agent runs as
**SYSTEM** at runtime.

### Capture-driver model (current vs. legacy)

| Windows version | Capture driver | Notes |
|---|---|---|
| Windows Server 2016 / 2019 / 2022 / 2025, Windows 10/11 | **`ndiscap.sys`** (in-box NDIS LWF) | Cisco-shipped; no Npcap. |
| Windows Server 2008 R2 | **Npcap** (Cisco-shipped, vendored version) | Older agents on 2008 R2 use Npcap. *"Do not swap Npcap"* on a 2008 R2 host running the agent — Cisco only qualifies the Npcap version they ship. |
| Pre-3.8 CSW agents on any Windows | **Npcap** | Same caveat — keep the Cisco-shipped Npcap. |

> **The "Npcap binds badly to clones" trap that older versions
> of this guide warned about applies specifically to the
> Npcap-on-2008R2 (and pre-3.8 agent) case.** It's still worth
> knowing about for legacy estates, but the recommended fix is
> the **Cisco-supported VDI flow** (`nostart=yes` /
> `-goldenImage`) — see the section above. Modern Windows
> hosts using `ndiscap.sys` are not affected by the Npcap
> cloning issue.

---

## Default install paths and files

> **Caveat — paths are release-dependent.** Cisco's chapter
> calls out the install directory in the *Install Windows
> Agents* section. Where this page lists a path, the
> authoritative answer is in your release's installer screen
> (and on the host's filesystem after a successful install).

| Path | Purpose |
|---|---|
| `C:\Program Files\Cisco Tetration\` | Agent binaries and supporting files (`CswEngine.exe`, `TetEnfC.exe`, etc.) |
| `C:\Program Files\Cisco Tetration\Logs\` | Agent logs (`TetSen.exe.log`, `TetEnf.exe.log` — note that the log file names retain the older `TetSen` / `TetEnf` prefix even though the running binaries are `CswEngine.exe` / `TetEnfC.exe`, per Cisco's *Connectivity Tests* section). |
| `HKLM\SYSTEM\CurrentControlSet\Services\CswAgent` | Windows service definition |
| `HKLM\SOFTWARE\Cisco\Tetration` *or release-equivalent* | Registry keys for cluster URL, activation key reference, agent state |

---

## Common gotchas (fleet-wide)

- **Cloned VMs from a baked template register as the build
  host.** Don't bake the agent into the template without using
  the VDI flag. Fix: install with `nostart=yes` (MSI) or
  `-goldenImage` (PowerShell) when baking; the service will
  start automatically on first boot of a clone with a different
  hostname. (See VDI section above.)
- **Service installs but stays in *Stopped* state.** Check the
  `Application` Event Log and the MSI / PowerShell installer log
  for agent errors. Most common cause: the activation key embedded
  in the installer was rotated; regenerate from the CSW UI.
- **WFP integration not engaged in Enforcement mode.** The agent
  ships *capable* of enforcement but enforcement is engaged
  only when the cluster pushes an Enforcement Agent Config
  Profile to the host. If the host is in a Deep-Visibility-only
  profile, WFP rules are not applied.
- **TLS handshake failed.** Per Cisco: agents validate cluster
  TLS against a local CA shipped with the installer. If a
  proxy or NGFW is decrypting egress, configure it to **bypass
  SSL/TLS decryption** for the CSW cluster FQDN. The exact CA
  filename and location are in the installer screen for your
  release; do not hand-craft `ca.pem` paths from older
  documentation.
- **Windows Defender flagging the agent or capture driver.**
  Configure exclusions per Cisco's *Configure Security
  Exclusions* (Table 3 lists `CswEngine.exe`, `TetEnfC.exe` and
  the install directory). Required as a pre-install step — see
  [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md).
- **Windows Server 2008 R2 only — clock drift on
  `tet-main.exe`.** Per Cisco's FAQ: the Go-built `tet-main.exe`
  on 2008 R2 with external NTP / domain-controller NTP can
  cause clock drift. Fix: periodic `w32tm /resync /force`.

Full troubleshooting in
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## See also

- [`../docs/00-official-references.md`](../docs/00-official-references.md) — Cisco's authoritative pages
- [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- [`../docs/02-sensor-types.md`](../docs/02-sensor-types.md)
- [`../docs/03-decision-matrix.md`](../docs/03-decision-matrix.md)
- [`../docs/04-rollout-strategy.md`](../docs/04-rollout-strategy.md)
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)
