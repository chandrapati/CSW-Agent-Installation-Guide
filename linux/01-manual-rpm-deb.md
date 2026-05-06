# Linux — Manual RPM / DEB Install

The simplest method: install the CSW agent package interactively
on a single host using the native package manager. Use this for
labs, troubleshooting, and to learn what the agent installs.

> **Authoritative source.** This page is a practitioner walk-
> through of Cisco's *Install Linux Agent using the Agent Image
> Installer Method* (in the
> [Deploy Software Agents on Workloads — Install Linux Agents](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
> chapter). Where the chapter and this page differ, **trust the
> chapter** for your release.

> **Not for fleet rollout.** This method doesn't scale. For
> more than a few hosts, prefer
> [`02-csw-generated-script.md`](./02-csw-generated-script.md)
> (one host at a time but pre-configured — the **Agent Script
> Installer**, which is Cisco's recommended method) or one of
> the automation methods (Ansible / Puppet / Chef / Salt).

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
  (specifically: **root privilege**, sufficient disk for the
  install + log directory, security-tooling exclusions
  configured per Cisco's *Configure Security Exclusions*
  guidance, host can reach the cluster on the right ports
  with **TLS pass-through** — see
  [`../operations/01-network-prereq.md`](../operations/01-network-prereq.md)
  for on-prem vs. SaaS port differences)
- Root or sudo on the workload
- The right `.rpm` / `.deb` package file for your CSW release
  and agent type, downloaded from *Manage → Workloads →
  Agents → Installer → Agent Image Installer*. The screen
  generates a per-cluster bundle that includes the cluster
  CA cert (`ca.cert`).

---

## Step 1 — Download the package

From any host with access to the CSW UI:

1. Log into the CSW UI
2. Navigate to *Manage → Workloads → Agents → Installer*
3. Choose **Agent Image Installer**
4. Choose the **OS / distribution / version** (and architecture)
5. Choose the **agent type** (Deep Visibility, or Deep Visibility
   + Enforcement — note that on modern releases, the **same
   package** ships both capabilities; whether enforcement
   actually engages is determined by the cluster-side Agent
   Config Profile, not by which package was installed)
6. Click *Download*

The downloaded bundle includes the agent package and the
cluster's `ca.cert` for the TLS chain.

The package name follows a pattern like:

```
tet-sensor-<version>.<distro>.x86_64.rpm        # RHEL family
tet-sensor-<version>.<distro>_amd64.deb         # Debian/Ubuntu family
```

(Cisco's *Install Linux Agent using the Agent Image Installer
Method* section enumerates the exact filename for each
distribution / architecture combo for the release you're
downloading. Trust that section for the canonical filename.)

Transfer the bundle to the workload (`scp`, `rsync`, or your
usual file-transfer mechanism).

---

## Step 2 — Verify the bundled CA cert is in place

The Agent Image Installer bundle ships the cluster's CA cert
as **`ca.cert`** alongside the package. Cisco's chapter calls
this out explicitly: *"`ca.cert` — Mandatory — CA certificate
for sensor communications."*

For SaaS clusters this is the public CA the agent needs. For
on-prem clusters this is your cluster's internal CA. **Do not
swap it for a different file** — the agent only validates
against this exact CA.

The package install itself places the `ca.cert` under the
agent's install directory (release-dependent — typically
`<install-dir>/conf/ca.cert`); you don't usually need to drop
it manually unless the chapter for your release tells you to.

---

## Step 3 — Install the package

### RHEL / CentOS / Rocky / AlmaLinux / Oracle Linux

Using `yum` / `dnf` (preferred — handles dependencies):

```bash
# RHEL 7 / CentOS 7
sudo yum install -y ./tet-sensor-3.x.y.z-1.el7.x86_64.rpm

# RHEL 8 / 9 / Rocky / AlmaLinux
sudo dnf install -y ./tet-sensor-3.x.y.z-1.el9.x86_64.rpm
```

Or with raw `rpm` (no dependency resolution):

```bash
sudo rpm -ivh tet-sensor-3.x.y.z-1.el9.x86_64.rpm
```

### SUSE Linux Enterprise Server (SLES)

```bash
sudo zypper install --no-confirm ./tet-sensor-3.x.y.z-1.sle15.x86_64.rpm
```

Or:

```bash
sudo rpm -ivh tet-sensor-3.x.y.z-1.sle15.x86_64.rpm
```

### Ubuntu / Debian

Using `apt` (preferred — handles dependencies):

```bash
sudo apt install -y ./tet-sensor-3.x.y.z-1.ubuntu22_amd64.deb
```

Or with raw `dpkg`:

```bash
sudo dpkg -i tet-sensor-3.x.y.z-1.ubuntu22_amd64.deb
# Resolve any missing dependencies that dpkg flagged:
sudo apt install -f
```

### Amazon Linux

```bash
# Amazon Linux 2 — RHEL 7 family
sudo yum install -y ./tet-sensor-3.x.y.z-1.el7.x86_64.rpm

# Amazon Linux 2023 — RHEL 9 family
sudo dnf install -y ./tet-sensor-3.x.y.z-1.el9.x86_64.rpm
```

### Post-install — SELinux and PAM considerations

The package install registers the `csw-agent` systemd service
and starts the agent processes (`tet-sensor`, and on
enforcement-enabled hosts `tet-enforcer`). On SELinux /
hardened-PAM hosts:

- **SELinux** must permit execute on the agent's install path.
  The package's default install directory is covered by the
  SELinux policy that the package installs. **If you used a
  non-standard install location** (some Agent Script Installer
  flags allow this), relabel:

  ```bash
  # Replace <custom-dir> with your custom install directory
  sudo semanage fcontext -a -t bin_t '<custom-dir>(/.*)?'
  sudo restorecon -Rv <custom-dir>
  ```

- **PAM** hardening: do not strip the `pam.d` fragments the
  package installs unless your security policy team has
  explicitly approved it.

Confirm SELinux isn't blocking the agent post-start:

```bash
sudo ausearch -m avc -ts recent | grep -iE 'csw|tet'
# Expected: no AVC denials. If you see denials, fix the labels.
```

---

## Step 4 — Confirm the service is running

```bash
sudo systemctl status csw-agent
```

Expected output (key lines):

```
● csw-agent.service - Cisco Secure Workload Agent
     Loaded: loaded (/usr/lib/systemd/system/csw-agent.service; enabled; ...)
     Active: active (running) since ...
```

> **If you see `csw-agent.service` instead of `csw-agent.service`**:
> you're on an older Tetration-era agent. The user-facing unit
> was renamed to `csw-agent` in current CSW releases. The
> commands and flags below are equivalent — substitute `tetd`
> for `csw-agent` if your install is the older naming.

If `Active: failed`, jump to Step 6.

---

## Step 5 — Confirm the agent registered with the cluster

In the CSW UI, *Manage → Workloads → Agents → Agent List*. The
new host should appear within 1–2 minutes of the service
starting. Initial status:

- *Running* — registered, telemetry flowing
- *Not Active* — installed but hasn't checked in (network /
  firewall issue)
- *Degraded* — registered but with a warning (kernel mismatch,
  outdated build, etc.)

For deeper verification (logs, ports, process tree), see
[`08-verification.md`](./08-verification.md).

---

## Step 6 — If something went wrong

### Service won't start

Check the install log:

```bash
sudo journalctl -u csw-agent -n 200
# Log file location is release-dependent — typically under
# /var/log/tetration/ or under the agent's install directory
sudo ls -la /var/log/tetration/ 2>/dev/null
```

Common patterns:

| Symptom | Likely cause | Fix |
|---|---|---|
| `kernel module compile failed` | kernel-headers package missing | `sudo yum install -y kernel-devel-$(uname -r)` (or `apt install linux-headers-$(uname -r)`); reinstall agent |
| `tls handshake failed: x509: certificate signed by unknown authority` | CA cert mismatch (cluster CA rotated, or wrong installer used) | Re-download the **current** Agent Image Installer bundle for your cluster (Cisco regenerates on CA rotation); reinstall; `sudo systemctl restart csw-agent` |
| `tls handshake failed: x509: certificate has expired or is not yet valid` | Clock skew | `sudo chronyc tracking` or `sudo timedatectl` to verify NTP sync |
| `connection refused` / `no route to host` | Firewall / network egress | Test the cluster destinations: on-prem use `nc -zv <CFG-SERVER> 443`, `nc -zv <COLLECTOR> 5640`, and (Enforcement) `nc -zv <ENFORCER> 5660`; SaaS uses 443 for everything |
| `connection timed out` to cluster IP | East-west firewall blocking | Network team — open the right ports per [`../operations/01-network-prereq.md`](../operations/01-network-prereq.md) |

### Package install itself failed

| Symptom | Likely cause | Fix |
|---|---|---|
| `requires: <library>.so` | Missing OS dependency | Install the named library; reinstall the agent |
| `package is intended for a different architecture` | Wrong `.rpm` / `.deb` for this OS | Re-download from the CSW UI for the correct OS family |
| `signature key not available` | RPM GPG key not imported | The CSW UI install screen documents the key import; or use `rpm -ivh --nodigest --nofiles --nosignature` for the lab only (do not bypass signatures in production) |

Full troubleshooting reference:
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## Step 7 — Cleanup (if you need to start over)

See [`../operations/05-uninstall.md`](../operations/05-uninstall.md)
for the full uninstall procedure. Quick version:

```bash
# RHEL family
sudo systemctl stop csw-agent
sudo yum remove -y tet-sensor

# Debian family
sudo systemctl stop csw-agent
sudo apt remove -y tet-sensor
```

The uninstall doc covers cleanup of leftover config / log
directories and decommissioning the agent record in the CSW
UI (*Manage → Workloads → Agents → Agent List → decommission*).

---

## When NOT to use this method

- **More than ~5 hosts.** Move to the CSW-generated script
  ([02](./02-csw-generated-script.md)) for medium fleets, or
  Ansible / Puppet / Chef / Salt for anything larger.
- **Air-gapped environments.** The CSW UI download is fine, but
  fleet rollout should go through your internal package repository
  ([03](./03-package-repo-satellite.md)).
- **Production change-controlled environments** where every install
  needs an audit trail. Use a config-management tool — its
  per-host log is your audit record.

---

## See also

- [`02-csw-generated-script.md`](./02-csw-generated-script.md) — the next step up: same package, with cluster details pre-baked
- [`04-ansible.md`](./04-ansible.md) — fleet automation
- [`08-verification.md`](./08-verification.md) — confirm the install
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md) — upgrade procedure
- [`../operations/05-uninstall.md`](../operations/05-uninstall.md) — clean uninstall
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md) — when something goes wrong
