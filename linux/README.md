# Linux — Installation Methods

Pick the runbook that matches your environment. All methods
produce the same end-state: the CSW agent installed on the
workload, the **`csw-agent`** systemd service running, and the
agent registered against the CSW cluster.

> **Authoritative source.** Every claim about service / package /
> path naming on this page comes from Cisco's
> [Deploy Software Agents on Workloads (4.0 On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
> chapter, specifically the *Install Linux Agents for Deep
> Visibility and Enforcement* and *Configure Security
> Exclusions* sections. If your release differs (older or newer
> than 4.0), trust the *Manage → Workloads → Agents → Installer*
> screen in your cluster — the screen text is generated for
> your specific release.

> **Before any of these methods**, confirm
> [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
> is satisfied. Most install failures trace back to a
> prerequisite gap, not the method itself.

---

## Methods in this folder

| # | Method | Best for | Doc |
|---|---|---|---|
| 01 | Manual RPM/DEB | One-off lab installs | [01-manual-rpm-deb.md](./01-manual-rpm-deb.md) |
| 02 | CSW-generated shell script (Agent Script Installer) | Small to medium fleets without an automation tool | [02-csw-generated-script.md](./02-csw-generated-script.md) |
| 03 | Internal Yum/APT repo (Satellite / Spacewalk / Pulp) | Air-gapped or change-controlled fleets | [03-package-repo-satellite.md](./03-package-repo-satellite.md) |
| 04 | Ansible playbook | Linux fleets where Ansible already runs | [04-ansible.md](./04-ansible.md) |
| 05 | Puppet manifest | Linux fleets where Puppet runs | [05-puppet.md](./05-puppet.md) |
| 06 | Chef recipe | Linux fleets where Chef runs | [06-chef.md](./06-chef.md) |
| 07 | Salt state | Linux fleets where Salt runs | [07-saltstack.md](./07-saltstack.md) |
| 08 | Verification | Confirming the install actually worked | [08-verification.md](./08-verification.md) |

> **Cisco-documented vs. community patterns.** Methods 01 and 02
> are documented directly in Cisco's *Install Linux Agents*
> section. Methods 03–07 are community / customer-derived
> automation patterns built on top of the Cisco-documented
> packages and Agent Script Installer; the patterns are common
> in production but the exact role / playbook / cookbook code
> in this repo is not Cisco-published.

---

## OS support snapshot

The Deep Visibility / Enforcement agent compiles or loads a
small kernel module per supported (distribution, version,
kernel) tuple. The official
[Compatibility Matrix](https://www.cisco.com/c/m/en_us/products/security/secure-workload-compatibility-matrix.html)
in the CSW documentation portal is the source of truth for
your specific CSW release. The list below is **illustrative**
of the breadth of distributions Cisco's chapter calls out;
exact versions / kernels may differ in your release.

| Distribution | Commonly-supported families |
|---|---|
| Red Hat Enterprise Linux (RHEL) | 7.x · 8.x · 9.x |
| CentOS / CentOS Stream | 7 (legacy) · Stream 8 / 9 |
| Rocky Linux | 8.x · 9.x |
| AlmaLinux | 8.x · 9.x |
| Oracle Linux | 7.x · 8.x · 9.x (RHCK and UEK kernels) |
| Ubuntu LTS | 18.04 · 20.04 · 22.04 · 24.04 |
| Debian | 10 · 11 · 12 |
| SUSE Linux Enterprise Server (SLES) | 12 SPx · 15 SPx |
| Amazon Linux | 2 · 2023 |

> **For OS / kernel combinations outside the matrix**: there
> is no separate "Universal Visibility" SKU in CSW 4.0. Your
> options are (1) move the workload to a supported OS / kernel,
> (2) use **NetFlow / ERSPAN ingestion** from the upstream
> network device, or (3) use a **Cloud Connector** if the
> workload is in a supported cloud — see
> [`../docs/02-sensor-types.md`](../docs/02-sensor-types.md).

---

## Agent flavours — same package, two modes

Per Cisco's *Install Linux Agents* section, the modern Linux
agent ships **one** package that contains both visibility and
enforcement capability. Whether it actually enforces is
determined by the cluster-side **Agent Config Profile**, not
by which package was installed.

| Mode | systemd service | What's running | Provides |
|---|---|---|---|
| Deep Visibility (default) | `csw-agent` | `tet-sensor` (and helpers) | Flow + process + software inventory + CVE lookup |
| Enforcement | `csw-agent` | `tet-sensor` + `tet-enforcer` (engaged via cluster config) | Deep Visibility + iptables / nftables enforcement |

**Process names** seen on a running host (per Cisco's
*Configure Security Exclusions* table — these are the names
you'd add to AV / EDR exclusion lists):

- `tet-sensor` — the agent process (Deep Visibility flow /
  process / inventory collection)
- `tet-enforcer` — the enforcement engine (loaded when the
  cluster pushes an Enforcement config profile)
- `tet-main` — auxiliary helper

> **Why "csw-agent" and not "tetd"?** Cisco renamed the
> user-facing systemd unit from the Tetration-era `tetd` to
> `csw-agent` in current CSW releases. Some older
> documentation, blog posts, and Tetration-era runbooks
> reference `tetd`; on a fresh CSW 4.x install the unit you'll
> manage is `csw-agent`. The underlying process binaries still
> carry the `tet-` prefix.

The CSW *Manage → Workloads → Agents → Installer* UI shows the
exact package name and download URL for your cluster and
chosen agent type. Always cross-check against that screen — it
reflects your specific release.

---

## Default install paths and files

> **Caveat — paths are release-dependent.** Cisco's chapter
> calls out the install directory in the per-platform install
> sections, but the exact path and config-file names have
> shifted between major releases (Tetration → CSW; on-prem →
> SaaS variants). The patterns below cover what you'll
> typically see on a CSW 4.x install. **Trust your host's
> filesystem and the Installer screen for your release** — if
> the layout differs, that is the authoritative answer.

| Path | Purpose |
|---|---|
| `/usr/local/tet/` *or* `/opt/cisco/tetration/` *or* `/opt/cisco/secure-workload/` | Agent binaries and supporting files (release-dependent) |
| `<install-dir>/conf/` | Agent configuration including the cluster CA cert (`ca.cert`, per Cisco's *Agent Image Installer* section) |
| `/var/log/tetration/` *or* `<install-dir>/log/` | Agent logs; check here when troubleshooting |
| `/usr/lib/systemd/system/csw-agent.service` *or* `/etc/systemd/system/csw-agent.service` | systemd unit |

> **The `/etc/tetration/ca.pem` path that older docs and some
> community write-ups reference is not the canonical location
> in CSW 4.x.** The CA cert ships **inside the installer
> bundle** and is placed under the agent's install directory
> as `ca.cert`. If you're following an older runbook that
> tells you to drop `ca.pem` under `/etc/tetration/`, verify
> first with the *Agent Image Installer* screen for your
> release.

---

## Common gotchas (fleet-wide)

- **`csw-agent` won't start: kernel module compile failure.**
  Almost always a kernel-update / agent-version mismatch.
  Either roll back the kernel, upgrade the agent to a release
  that supports the new kernel, or stay in Deep Visibility on
  a kernel known good for your installed agent version.
- **Agent registers but reports "scope: Default".** The
  activation key embedded in the installer determined the
  scope. To move the workload, change the scope label in the
  CSW UI, not on the host.
- **Agent health "kernel mismatch"** after an OS patch. See
  [`../operations/04-upgrade.md`](../operations/04-upgrade.md).
- **TLS handshake failed: x509 unknown authority.** Confirm
  the agent's bundled `ca.cert` matches the cluster CA;
  reinstall from the *current* installer for your cluster
  (regenerated installers track cluster CA rotations);
  restart with `systemctl restart csw-agent`.

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
