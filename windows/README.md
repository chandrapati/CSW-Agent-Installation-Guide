# Windows — Installation Methods

Pick the runbook that matches your environment. All methods produce
the same end-state: the CSW Windows agent (`TetSensor.msi`)
installed, running as a Windows service (binary name
`tetsen.exe`), and registered against the CSW cluster.

> **Before any of these methods**, confirm
> [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md) is
> satisfied. Most install failures trace back to a prerequisite gap,
> not the method itself.

> **Critical — read before any deployment that uses VM templates,
> Citrix MCS / PVS, VMware Instant Clones, or AWS / Azure / GCP
> golden images.** The Windows TetSensor service captures network
> flows using **NPCAP**. NPCAP binds to the network stack at
> install time. **When a new VM is cloned from a template that
> already has TetSensor installed, NPCAP does not bind cleanly to
> the cloned VM's network stack** — capture silently fails on the
> clones. There is no Windows equivalent of the Linux
> `--golden-image` installer flag at this writing. The official
> guidance is to **install TetSensor as a post-clone step** (SCCM,
> Intune, GPO startup script, or a first-boot PowerShell
> invocation of the CSW PowerShell installer) rather than baking
> it into the template. See
> [`../docs/00-official-references.md`](../docs/00-official-references.md)
> for the User Guide reference.

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

---

## OS support snapshot

The Windows agent supports current Windows Server releases out of
the box. Always cross-check the **Compatibility Matrix** in the
CSW documentation portal for your specific CSW release.

| Distribution | Common supported versions |
|---|---|
| Windows Server | 2012 R2 · 2016 · 2019 · 2022 · 2025 |
| Windows Client (when allowed by the platform team) | 10 · 11 |

For laptops / desktops in a user-endpoint role, **a CSW agent is
not required** when the endpoint runs **Cisco AnyConnect Secure
Mobility Client with NVM** or is registered with **Cisco ISE**.
See [`../docs/05-anyconnect-ise-alternatives.md`](../docs/05-anyconnect-ise-alternatives.md).

---

## Sensor flavours on Windows

| Variant | MSI pattern | Service name | Service binary | Provides |
|---|---|---|---|---|
| Deep Visibility | `TetSensor.msi` (or `TetrationAgentInstaller-x64.msi` per release) | `TetSensor` (and supporting services) | `tetsen.exe` | Flow + process + software inventory + CVE lookup |
| Enforcement | Same MSI; Enforcement engaged via agent profile in CSW UI | `TetSensor` + Windows Filtering Platform (WFP) integration | `tetsen.exe` + WFP filters | Deep Visibility + workload-side firewall enforcement |

The CSW *Manage → Agents → Install Agent* UI shows the exact MSI
file name for your cluster and chosen sensor type. The agent
runs as **SYSTEM** at runtime.

### NPCAP — what to know

- TetSensor uses **NPCAP** to capture network flows on Windows.
  Cisco ships the supported NPCAP version with the installer.
- **Do not swap NPCAP** on a host running TetSensor. Running an
  NPCAP version (or NPCAP configuration) that CSW has not
  qualified can cause unknown OS performance or stability
  issues, per the CSW 4.0 User Guide.
- Network performance on the host may show a measurable impact
  from TetSensor + NPCAP. Plan capacity accordingly on
  flow-heavy hosts (load balancers, DNS / proxy hosts).

---

## Default install paths and files

| Path | Purpose |
|---|---|
| `%ProgramFiles%\Cisco Tetration\` | Sensor binaries and supporting files (older releases used `C:\Program Files\Cisco\Tetration\`) |
| `%ProgramData%\Cisco\Tetration\` | Sensor configuration and state |
| `%ProgramData%\Cisco\Tetration\Logs\` | Sensor logs; check here when troubleshooting |
| `HKLM\SOFTWARE\Cisco\Tetration` | Registry keys for cluster URL, activation key reference, agent state |
| Service registry: `HKLM\SYSTEM\CurrentControlSet\Services\TetSensor` | Windows service definition |

The exact paths can change between major CSW releases. If the
filesystem layout you find on a freshly installed host differs from
the table above, trust the host — and confirm against your
release's install guide.

---

## Common gotchas (fleet-wide)

- **Cloned VMs from a TetSensor-baked template silently capture
  no flows.** This is the NPCAP cloning trap (see the warning at
  the top of this doc). Fix: do not bake TetSensor into the
  template; install as a post-clone step via SCCM / Intune / GPO
  / a first-boot PowerShell call to the CSW PowerShell
  installer. Triggers: VMware templates + Instant Clones, Citrix
  MCS / PVS, AWS / Azure / GCP custom images, Hyper-V VM
  templates.
- **Service installs but stays in *Stopped* state.** Check the
  Windows Event Log: `Application` log → source `TetSensor`.
  The most common cause is the activation key embedded in the
  installer was rotated; regenerate from the CSW UI.
- **WFP integration not engaged in Enforcement mode.** Confirm in
  CSW UI that the agent profile is *Enforcement* not
  *Visibility-only*. The WFP rules apply only when the cluster
  pushes the policy. Note: by default, agents have the
  *capability* to enforce but enforcement is **disabled** until
  you turn it on per host.
- **TLS handshake failed.** Place the cluster CA in
  `%ProgramData%\Cisco\Tetration\conf\ca.pem` (or whatever path
  your release expects), restart the service. Note: CSW agents
  reject any unexpected TLS certificate, so a TLS-decrypting
  proxy must be configured to bypass the cluster FQDN.
- **Windows Defender flagging the kernel filter driver or the
  NPCAP install.** Configure exclusions in Defender / your EDR
  per Cisco's published guidance — required as a pre-install
  step (see [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)).
- **Unsupported NPCAP version present on the host pre-install.**
  Remove NPCAP first, then run the TetSensor installer so the
  Cisco-bundled NPCAP version installs cleanly.

Full troubleshooting in
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## See also

- [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- [`../docs/02-sensor-types.md`](../docs/02-sensor-types.md)
- [`../docs/03-decision-matrix.md`](../docs/03-decision-matrix.md)
- [`../docs/04-rollout-strategy.md`](../docs/04-rollout-strategy.md)
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)
