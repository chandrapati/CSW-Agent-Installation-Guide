# Linux — Manual RPM / DEB Install

The simplest method: install the `tet-sensor` package interactively
on a single host using the native package manager. Use this for
labs, troubleshooting, and to learn what the agent installs.

> **Not for fleet rollout.** This method doesn't scale. For more
> than a few hosts, prefer
> [`02-csw-generated-script.md`](./02-csw-generated-script.md) (one
> host at a time but pre-configured) or one of the automation
> methods (Ansible / Puppet / Chef / Salt).

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
  (specifically: **root or Administrator privilege**, **≥ 1 GB**
  storage, security-tooling exclusions configured, host can
  reach the cluster on TCP/443 with TLS pass-through)
- Root or sudo on the workload
- The right `.rpm` / `.deb` package file for your CSW release and
  sensor type, downloaded from the CSW *Manage → Agents → Install
  Agent* UI
- For on-prem clusters: the cluster CA chain (`ca.pem`)

---

## Step 1 — Download the package

From any host with access to the CSW UI:

1. Log into the CSW UI
2. Navigate to *Manage → Agents → Install Agent* (the menu may also
   read *Sensors* in older releases)
3. Choose the **OS / distribution / version**
4. Choose the **sensor type** (Deep Visibility or Enforcement)
5. Choose the **target scope** (this is baked into the package's
   embedded activation key)
6. Click *Download package*

The downloaded file follows a naming convention similar to:

```
tet-sensor-3.x.y.z-1.<distro>.x86_64.rpm        # RHEL family
tet-sensor-3.x.y.z-1.<distro>_amd64.deb         # Debian/Ubuntu family
```

(For Enforcement: `tet-sensor-enforcer-...` — same naming pattern.)

Transfer the file to the workload (`scp`, `rsync`, or your usual
file-transfer mechanism).

---

## Step 2 — (On-prem clusters only) Place the cluster CA

If the CSW cluster uses a private / internal CA, deposit the CA
chain so the agent's TLS handshake succeeds:

```bash
sudo mkdir -p /etc/tetration
sudo cp ca.pem /etc/tetration/ca.pem
sudo chmod 644 /etc/tetration/ca.pem
```

For SaaS clusters this step is unnecessary — public CA validation
just works.

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

### Post-install — `tet-sensor` user, SELinux, PAM

The package install creates a special user **`tet-sensor`** on
the host (the runtime identity for parts of the agent that
don't need full root):

```bash
id tet-sensor
# Expected: uid=NNN(tet-sensor) gid=NNN(tet-sensor) groups=NNN(tet-sensor)
```

If the host is **SELinux-enforcing** or has **PAM hardening**,
two things must hold for the agent to actually start cleanly:

1. PAM must allow the `tet-sensor` user to run the agent
   (the install drops a standard `pam.d` fragment — do not
   strip it during host hardening).
2. SELinux must permit execute on the agent's install path. The
   default `/usr/local/tet/` install location is covered by the
   SELinux policy that the package installs. **If you used
   `--basedir=<dir>` (via the CSW-generated script) to install
   somewhere non-standard**, you must relabel:

   ```bash
   # Replace /opt/csw with your custom basedir
   sudo semanage fcontext -a -t bin_t '/opt/csw(/.*)?'
   sudo restorecon -Rv /opt/csw
   ```

Confirm SELinux isn't blocking the agent post-start:

```bash
sudo ausearch -m avc -ts recent | grep -i tet
# Expected: no AVC denials. If you see denials, fix the labels.
```

---

## Step 4 — Confirm the service is running

```bash
sudo systemctl status tetd
```

Expected output (key lines):

```
● tetd.service - Cisco Secure Workload sensor
     Loaded: loaded (/usr/lib/systemd/system/tetd.service; enabled; ...)
     Active: active (running) since ...
```

If `Active: failed`, jump to Step 6.

---

## Step 5 — Confirm the agent registered with the cluster

In the CSW UI, *Manage → Agents → Software Agents*. The new host
should appear within 1–2 minutes of `tetd` starting. Initial
status:

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
sudo journalctl -u tetd -n 200
sudo less /var/log/tetration/tet-sensor.log
```

Common patterns:

| Symptom | Likely cause | Fix |
|---|---|---|
| `kernel module compile failed` | kernel-headers package missing | `sudo yum install -y kernel-devel-$(uname -r)` (or `apt install linux-headers-$(uname -r)`); reinstall agent |
| `tls handshake failed: x509: certificate signed by unknown authority` | CA chain not deposited | Place `ca.pem` per Step 2; `sudo systemctl restart tetd` |
| `tls handshake failed: x509: certificate has expired or is not yet valid` | Clock skew | `sudo chronyc tracking` or `sudo timedatectl` to verify NTP sync |
| `connection refused` / `no route to host` | Firewall / network egress | `curl -v https://<cluster-vip>:443/` from the host to test connectivity |
| `connection timed out` to cluster IP | East-west firewall blocking | Network team — open 443/TCP outbound to the cluster collector VIP |

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
sudo systemctl stop tetd
sudo yum remove -y tet-sensor

# Debian family
sudo systemctl stop tetd
sudo apt remove -y tet-sensor
```

The uninstall doc covers cleanup of `/etc/tetration/`,
`/var/log/tetration/`, and the agent's record in the CSW UI
(*Manage → Agents → decommission*).

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
