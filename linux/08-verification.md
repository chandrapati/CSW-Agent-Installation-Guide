# Linux — Verification

The agent is installed. How do you confirm it's actually working?
This doc is the post-install checklist.

> Pair these checks with the **CSW UI** (*Manage → Agents →
> Software Agents*). The UI tells you what the cluster sees; this
> doc tells you what the workload knows. Both views need to agree.

---

## Five-minute health check

Run these commands on the workload after install:

```bash
# 1. Service is active
systemctl is-active tetd
# Expected: active

# 2. Service is enabled at boot
systemctl is-enabled tetd
# Expected: enabled

# 3. Process tree
pgrep -af tet
# Expected: at least the tet-sensor / tet-engine processes

# 4. Recent logs (no errors)
sudo tail -50 /var/log/tetration/tet-sensor.log
# Expected: registration success, telemetry batches uploading

# 5. Outbound connectivity to cluster
sudo ss -tnp | grep tet
# Expected: ESTABLISHED connection to cluster IP on 443
```

If all five pass, the workload-side install is healthy. Cross-check
in the UI to confirm registration.

---

## Detailed verification

### 1. Confirm the package is installed and at the expected version

```bash
# RHEL family
rpm -q tet-sensor
# Expected output: tet-sensor-3.x.y.z-1.el9.x86_64

# Debian family
dpkg -l tet-sensor | tail -1
# Expected: ii  tet-sensor  3.x.y.z-1   amd64   ...

# Show installed files (helpful for "where did it put X?")
rpm -ql tet-sensor | head -50
# or
dpkg -L tet-sensor | head -50
```

### 2. Confirm `tetd` is running and enabled

```bash
sudo systemctl status tetd
```

Expected output (key lines):

```
● tetd.service - Cisco Secure Workload sensor
     Loaded: loaded (/usr/lib/systemd/system/tetd.service; enabled; preset: ...)
     Active: active (running) since <timestamp>
   Main PID: <pid> (tet-sensor)
      Tasks: <n>
     Memory: <m>M
        CPU: <t>s
     CGroup: /system.slice/tetd.service
             ├─<pid> /usr/local/tet/tet-sensor
             └─<pid> /usr/local/tet/tet-engine
```

If `Active: failed`, jump to the troubleshooting section below.

### 3. Confirm outbound connectivity to the cluster

```bash
# What CSW thinks the cluster destination is, per the agent config:
sudo grep -E '(CLUSTER_FQDN|HTTPS_PROXY|ACTIVATION)' /etc/tetration/sensor.conf

# Test the destination directly
curl -v https://<cluster-fqdn>:443/ 2>&1 | head -20
# Look for: "* Connected to <cluster> ... port 443" and a TLS handshake
# A 404/403 from the cluster *web* server is fine — the agent uses
# different paths but proving you can reach the host on 443 is enough.
```

Active connections from the sensor:

```bash
sudo ss -tnp | grep -E 'tet-sensor|tet-engine'
# Expected: an ESTABLISHED connection on remote port 443
```

### 4. Confirm time sync

TLS handshake fails on clock skew:

```bash
chronyc tracking | grep -E 'Reference ID|Stratum|System time'
# Or:
timedatectl
# Expected: System clock synchronized: yes
```

### 5. Confirm the agent registered with the cluster

In the **CSW UI**:

1. *Manage → Agents → Software Agents*
2. Search by hostname
3. Look at the **Status** column:
   - **Running** — registered, telemetry flowing, healthy
   - **Not Active** — installed but not checking in (network /
     firewall / activation issue)
   - **Degraded** — registered with a warning (kernel mismatch,
     outdated build, throttled telemetry)

The host details panel shows:

- **Last checkin** — should be within the last few minutes
- **Sensor type** — Deep Visibility / Enforcement / UV
- **Software version** — matches what `rpm -q` / `dpkg -l` shows
- **Scope** — the scope the activation key targeted
- **Inventory tags** — facts the agent reports (OS, kernel, IP,
  MAC, hostname, etc.)

### 6. Confirm telemetry is flowing

In the **CSW UI**:

1. *Investigate → Flows*
2. Filter by the workload's IP or hostname
3. Within ~2 minutes of `tetd` starting, you should see flows

If the host is registered but no flows appear after 5+ minutes:

- The host genuinely has no traffic (check on a host with known
  inbound/outbound flows; a brand new VM might have very little)
- Sensor health is *Degraded*; check the UI for the specific
  warning
- The agent is collecting but the cluster is dropping due to a
  collector throttle (rare; check with the cluster team)

### 7. Confirm the inventory is enriched

In the **CSW UI**:

1. *Organize → Inventory*
2. Find the workload by IP / hostname
3. The detail panel should show:
   - **Software inventory** — installed packages with versions
   - **Vulnerabilities** — CVE list with severities (after the
     first vuln-scan cycle, typically 5–15 minutes)
   - **Process inventory** — observed running processes with
     binary paths and command lines

If software inventory is empty after 30 minutes, see the
troubleshooting doc.

---

## Verification automation snippets

### Bash — full check on one host

```bash
#!/usr/bin/env bash
set -uo pipefail

mark_pass() { printf '\e[32m PASS\e[0m  %s\n' "$1"; }
mark_fail() { printf '\e[31m FAIL\e[0m  %s\n' "$1"; }
mark_warn() { printf '\e[33m WARN\e[0m  %s\n' "$1"; }

# 1. Package installed
if rpm -q tet-sensor &>/dev/null || dpkg -l tet-sensor &>/dev/null 2>&1; then
  mark_pass "tet-sensor package installed"
else
  mark_fail "tet-sensor package not installed"
fi

# 2. Service active
if systemctl is-active --quiet tetd; then
  mark_pass "tetd service active"
else
  mark_fail "tetd service not active"
fi

# 3. Service enabled
if systemctl is-enabled --quiet tetd; then
  mark_pass "tetd service enabled at boot"
else
  mark_warn "tetd service not enabled at boot"
fi

# 4. Recent connection on 443
if ss -tn | awk '$5 ~ /:443$/ {print}' | grep -qE 'ESTAB'; then
  mark_pass "ESTABLISHED connection on 443"
else
  mark_warn "no ESTABLISHED connection on 443 found"
fi

# 5. No recent ERROR in agent log
if [[ -f /var/log/tetration/tet-sensor.log ]]; then
  if tail -200 /var/log/tetration/tet-sensor.log | grep -qE 'ERROR|FATAL'; then
    mark_warn "ERROR/FATAL in last 200 log lines — review"
  else
    mark_pass "no ERROR/FATAL in last 200 log lines"
  fi
else
  mark_warn "no agent log file at /var/log/tetration/tet-sensor.log"
fi
```

### Ansible — fleet-wide verification play

See [`04-ansible.md`](./04-ansible.md) → "Verification play (run
after install)".

---

## Common findings during verification

### "Service active, no flows in UI after 10 min"

1. Confirm in UI that the host is in *Running* state, not
   *Not Active*
2. Confirm time sync (`chronyc tracking` shows recent sync)
3. Tail `tet-sensor.log` for `Successfully sent N records` lines
4. If the log shows uploads but the UI doesn't show flows, check
   with the cluster team — collector-side issue

### "Agent installed but UI says Not Active"

1. Confirm outbound 443 reaches the cluster from the workload
2. Confirm the activation key in `/etc/tetration/sensor.conf`
   matches the one currently valid in the CSW UI
3. Check `tet-sensor.log` for `tls handshake failed` or
   `unauthorized` patterns
4. If on-prem cluster: confirm `/etc/tetration/ca.pem` matches
   the cluster CA
5. As a last resort: regenerate the install script in the UI for
   the correct scope and rerun

### "Service flapping (running → failed → running)"

1. Check for kernel module compile failures:
   `dmesg | grep -i tet` or `journalctl -u tetd | grep -i kernel`
2. Confirm `kernel-headers` matches `uname -r`
3. Confirm OS / kernel are on the [Compatibility Matrix](https://www.cisco.com/c/m/en_us/products/security/secure-workload-compatibility-matrix.html)
   for the installed agent version
4. Open a TAC case with the evidence bundle from
   [`../operations/08-evidence-audit.md`](../operations/08-evidence-audit.md)

### "Software inventory empty in UI after 30 min"

1. Confirm the workload's package manager is one the agent
   supports (`yum`/`dnf`/`apt`/`zypper`)
2. Check the agent log for inventory-walk errors
3. Trigger a manual inventory refresh per the troubleshooting doc
4. If the host has an unusual package layout (custom prefix
   binaries, etc.), the inventory walk may need adjustment

---

## See also

- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md) — when verification fails
- [`../operations/08-evidence-audit.md`](../operations/08-evidence-audit.md) — what to gather before a TAC case
- [`../docs/04-rollout-strategy.md`](../docs/04-rollout-strategy.md) — what to verify between Monitor / Simulate / Enforce phases
