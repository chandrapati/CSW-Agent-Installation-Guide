# Windows — Installation Methods

Pick the runbook that matches your environment. All methods produce
the same end-state: the CSW Windows agent (`TetSensor.msi`)
installed, running as a Windows service, and registered against
the CSW cluster.

> **Before any of these methods**, confirm
> [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md) is
> satisfied. Most install failures trace back to a prerequisite gap,
> not the method itself.

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

For laptops / desktops in a user-endpoint role, the recommended
sensor is **AnyConnect Network Visibility Module (NVM)** delivered
via Cisco Secure Client, not the Windows server agent.

---

## Sensor flavours on Windows

| Variant | MSI pattern | Service name | Provides |
|---|---|---|---|
| Deep Visibility | `TetSensor.msi` (or `TetrationAgentInstaller-x64.msi` per release) | `TetSensor` (and supporting services) | Flow + process + software inventory + CVE lookup |
| Enforcement | Same MSI; Enforcement engaged via agent profile in CSW UI | `TetSensor` + Windows Filtering Platform (WFP) integration | Deep Visibility + workload-side firewall enforcement |

The CSW *Manage → Agents → Install Agent* UI shows the exact MSI
file name for your cluster and chosen sensor type.

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

- **Service installs but stays in *Stopped* state.** Check the
  Windows Event Log: `Application` log → source `TetSensor`.
  The most common cause is the activation key embedded in the
  installer was rotated; regenerate from the CSW UI.
- **WFP integration not engaged in Enforcement mode.** Confirm in
  CSW UI that the agent profile is *Enforcement* not
  *Visibility-only*. The WFP rules apply only when the cluster
  pushes the policy.
- **TLS handshake failed.** Place the cluster CA in
  `%ProgramData%\Cisco\Tetration\conf\ca.pem` (or whatever path
  your release expects), restart the service.
- **Windows Defender flagging the kernel filter driver.** Add an
  allow-list exception per Cisco's published guidance for your
  Defender / EDR product.

Full troubleshooting in
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## See also

- [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- [`../docs/02-sensor-types.md`](../docs/02-sensor-types.md)
- [`../docs/03-decision-matrix.md`](../docs/03-decision-matrix.md)
- [`../docs/04-rollout-strategy.md`](../docs/04-rollout-strategy.md)
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)
