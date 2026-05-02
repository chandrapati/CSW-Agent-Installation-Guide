# Linux — Installation Methods

Pick the runbook that matches your environment. All methods produce
the same end-state: a `tet-sensor` (Deep Visibility) or
`tet-sensor-enforcer` (Enforcement) package installed on the
workload, with the `tetd` systemd service running and registered
against the CSW cluster.

> **Before any of these methods**, confirm
> [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md) is
> satisfied. Most install failures trace back to a prerequisite gap,
> not the method itself.

---

## Methods in this folder

| # | Method | Best for | Doc |
|---|---|---|---|
| 01 | Manual RPM/DEB | One-off lab installs | [01-manual-rpm-deb.md](./01-manual-rpm-deb.md) |
| 02 | CSW-generated shell script | Small to medium fleets without an automation tool | [02-csw-generated-script.md](./02-csw-generated-script.md) |
| 03 | Internal Yum/APT repo (Satellite / Spacewalk / Pulp) | Air-gapped or change-controlled fleets | [03-package-repo-satellite.md](./03-package-repo-satellite.md) |
| 04 | Ansible playbook | Linux fleets where Ansible already runs | [04-ansible.md](./04-ansible.md) |
| 05 | Puppet manifest | Linux fleets where Puppet runs | [05-puppet.md](./05-puppet.md) |
| 06 | Chef recipe | Linux fleets where Chef runs | [06-chef.md](./06-chef.md) |
| 07 | Salt state | Linux fleets where Salt runs | [07-saltstack.md](./07-saltstack.md) |
| 08 | Verification | Confirming the install actually worked | [08-verification.md](./08-verification.md) |

---

## OS support snapshot

The Deep Visibility / Enforcement sensors compile a small kernel
module per supported (distribution, version, kernel) tuple. The
official **Compatibility Matrix** in the CSW documentation portal
is the source of truth for your specific CSW release. The list
below is illustrative.

| Distribution | Common supported versions |
|---|---|
| Red Hat Enterprise Linux (RHEL) | 7.x · 8.x · 9.x |
| CentOS Stream | 8 · 9 |
| Rocky Linux | 8.x · 9.x |
| AlmaLinux | 8.x · 9.x |
| Oracle Linux | 7.x · 8.x · 9.x (RHCK and UEK kernels) |
| Ubuntu LTS | 18.04 · 20.04 · 22.04 · 24.04 |
| Debian | 10 · 11 · 12 |
| SUSE Linux Enterprise Server (SLES) | 12 SPx · 15 SPx |
| Amazon Linux | 2 · 2023 |

For OS / kernel combinations outside the matrix, use the **Universal
Visibility (UV)** sensor variant — it's user-space only, supports a
broader matrix, but does not enforce.

---

## Sensor flavours

| Variant | Package name pattern | systemd service | Provides |
|---|---|---|---|
| Deep Visibility | `tet-sensor` | `tetd` | Flow + process + software inventory + CVE lookup |
| Enforcement | `tet-sensor-enforcer` (or Deep Visibility package + Enforcement profile, depending on release) | `tetd` (+ enforcer module) | Deep Visibility + workload-side firewall enforcement |
| Universal Visibility | `tet-sensor` (UV build) | `tetd` | Flow + process (lighter) + inventory; no enforcement |

The CSW *Manage → Agents → Install Agent* UI shows the exact
package name and download URL for your cluster and chosen sensor
type. Always cross-check against that screen.

---

## Default install paths and files

| Path | Purpose |
|---|---|
| `/usr/local/tet/` | Sensor binaries and supporting files (some releases use `/opt/cisco/tetration/` instead — release-dependent) |
| `/etc/tetration/` | Sensor configuration; on-prem clusters typically have a `ca.pem` here for TLS trust |
| `/var/log/tetration/` | Sensor logs; check here when troubleshooting |
| `/etc/systemd/system/tetd.service` | systemd unit (or `/usr/lib/systemd/system/tetd.service`) |

The exact paths can change between major CSW releases. If the
filesystem layout you find on a freshly installed host differs from
the table above, trust the host — and confirm against your
release's install guide. The patterns in this repo work for either
layout.

---

## Common gotchas (fleet-wide)

- **`tetd` won't start: kernel module compile failure.** Almost
  always a kernel-update / agent-version mismatch. Either roll
  back the kernel, upgrade the agent to a release that supports
  the new kernel, or move the host to UV.
- **Agent registers but reports "scope: Default".** The activation
  key embedded in the installer determined the scope. To move the
  workload, change the scope label in the CSW UI, not on the host.
- **Sensor health "kernel mismatch"** after an OS patch. See
  [`../operations/04-upgrade.md`](../operations/04-upgrade.md).
- **TLS handshake failed: x509 unknown authority.** Place the
  cluster CA in `/etc/tetration/ca.pem`; restart `tetd`.

Full troubleshooting in
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## See also

- [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- [`../docs/02-sensor-types.md`](../docs/02-sensor-types.md)
- [`../docs/03-decision-matrix.md`](../docs/03-decision-matrix.md)
- [`../docs/04-rollout-strategy.md`](../docs/04-rollout-strategy.md)
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)
