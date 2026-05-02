# Linux — CSW-Generated Shell Script Install

The CSW cluster generates a self-contained shell script for each
(OS family, sensor type, scope) combination. Run it on the
workload and the script handles **everything**: package download,
TLS trust setup, activation key, scope assignment, service start,
registration. This is the **most common method** in real
enterprise deployments — especially for the first month of a
POV — because it removes every manual step except "run the
script as root".

> The script is **per-tenant and per-cluster**. The activation key
> baked into it is tied to the CSW cluster and (optionally) the
> chosen scope. Do not share the script across tenants or
> clusters; regenerate it for each.

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- Root or sudo on the workload
- Either: outbound HTTPS from the workload to the CSW cluster
  (the script downloads its package payload from the cluster);
  **or** the script downloaded once and copied to the workload
  via your file-transfer mechanism

---

## Step 1 — Generate the script in the CSW UI

1. Log into the CSW UI
2. Navigate to *Manage → Agents → Install Agent*
3. Choose the **Linux distribution and version**
4. Choose the **sensor type** (Deep Visibility or Enforcement)
5. Choose the **target scope** — the workload will land in this
   scope on first registration; the agent inherits the scope's
   labels
6. Click *Download Installer Script* (the script is a `.sh` file
   named something like `install_sensor.sh` or `tetration-installer-<scope>-linux.sh`)

The downloaded script bundles:

- The activation key for your cluster
- The cluster collector VIP (or SaaS hostname)
- The cluster CA chain (if on-prem with private CA)
- The download URL of the agent package
- The `--scope=` argument or its equivalent

You don't need to edit the script — the cluster has already
configured it for the choices you made.

---

## Step 2 — Transfer to the workload

Two patterns:

### Pattern A — workload has direct egress to the cluster

If the workload can reach the CSW cluster directly (the typical
case for cloud workloads or for on-prem hosts inside the data
centre with the cluster), copy only the script to the host and
let it download the package payload itself:

```bash
scp install_sensor.sh user@workload:/tmp/
```

### Pattern B — script downloaded once, distributed via your channel

If the workload doesn't have direct egress, you can download the
package payload to the script's host once, package both together,
and ship them to the workload. Some script versions accept a
`--no-download` flag and read from a local path; if not, fall
back to the manual RPM/DEB method ([01](./01-manual-rpm-deb.md))
or the internal repo method ([03](./03-package-repo-satellite.md)).

---

## Step 3 — Run the script

```bash
chmod +x /tmp/install_sensor.sh
sudo /tmp/install_sensor.sh
```

The script:

1. Checks the OS / kernel against its supported list
2. (Optional) prompts for proxy details if it can't reach the
   cluster directly
3. Downloads the agent package over HTTPS from the cluster
4. Validates the package signature
5. Deposits the cluster CA chain (on-prem) at `/etc/tetration/ca.pem`
6. Installs the package via `rpm` / `dpkg`
7. Writes the cluster URL and activation key to
   `/etc/tetration/sensor.conf` (or release-equivalent)
8. Starts and enables the `tetd` service
9. Registers with the cluster

Expected end-of-run output (paraphrased):

```
[INFO] Sensor installation complete
[INFO] Service tetd started and enabled
[INFO] Sensor registered with cluster <cluster-vip>
[INFO] Workload UUID: <uuid>
```

If you see any `[ERROR]` line, jump to the troubleshooting block
below.

---

## Step 4 — Confirm registration in the CSW UI

In CSW *Manage → Agents → Software Agents*, the new host should
appear within 1–2 minutes of script completion, with status
*Running* and the scope you selected at script-generation time.

For deeper verification, see [`08-verification.md`](./08-verification.md).

---

## Common script flags

The exact flag set varies by CSW release; the script's `--help`
is the source of truth. Common flags you'll see:

| Flag | Purpose |
|---|---|
| `--proxy <url>` | Send all agent traffic through an HTTP proxy |
| `--proxy-user <user>` / `--proxy-password <pwd>` | Proxy auth (use a credential store, not literals in scripts) |
| `--no-download` | Don't download the package; read it from a local path |
| `--package-path <file>` | Path to a pre-downloaded package |
| `--cluster-fqdn <host>` | Override the cluster destination |
| `--ca-cert <path>` | Override the CA chain path |
| `--scope-label <key=value>` | Add an extra label at registration time |
| `--silent` | Non-interactive; for use in pipelines |
| `--help` / `-h` | Show all flags for your script's release |

Always run `./install_sensor.sh --help` first if you're not sure.

---

## Pushing the script to many hosts at once

The script is fundamentally a per-host operation, but you can
parallelise the per-host invocation. Common patterns:

### A jump host with `parallel-ssh` (or `mssh`)

```bash
# inventory.txt: one hostname per line
parallel-ssh -h inventory.txt -i \
  "scp install_sensor.sh ${TARGET}:/tmp/ && \
   ssh ${TARGET} sudo /tmp/install_sensor.sh"
```

### A simple `for` loop (small fleets)

```bash
for h in $(cat inventory.txt); do
  scp install_sensor.sh "$h":/tmp/
  ssh "$h" "sudo bash /tmp/install_sensor.sh"
done
```

### From a CI/CD job

If you have a CI/CD runner that can SSH (or use cloud-native
agent execution like AWS SSM, Azure Run Command, GCP OS Login),
wrap the same two commands (`scp` + `ssh sudo`) in a job step.

For anything beyond a few dozen hosts, **stop using the script in
a loop and switch to Ansible** ([04](./04-ansible.md)) — it gives
you idempotency, retry logic, parallel execution, and an audit
log out of the box.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Script exits with `download failed: cannot reach <cluster>` | Workload can't reach the cluster on 443/TCP | Test with `curl -v https://<cluster>:443/`; open the firewall port; or pre-download the package and pass `--no-download --package-path /tmp/pkg.rpm` |
| Script reports `OS not supported` | OS / kernel not on the matrix for this CSW release | Check the Compatibility Matrix; consider Universal Visibility for niche kernels |
| `tetd` started but registration is *Not Active* in UI | Outbound 443 reaches the cluster but the activation key was rejected | Regenerate the script in the UI (the key may have been rotated); rerun |
| Registers under wrong scope | Script was generated for a different scope | Regenerate for the correct scope; or move the workload in the UI by changing the scope label |
| Hangs at "validating package signature" | Time skew | `chronyc tracking` / `timedatectl` to confirm clock sync |

For deeper troubleshooting, see
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## When this is the right method

- **First-month POV / pilot deployments** where the team wants to
  get the agent on hosts quickly without standing up Ansible
  pipelines.
- **Small to medium fleets** (up to a few hundred hosts) where the
  team has a remote-execution channel (jump host, SSM, etc.) but
  no full config-management pipeline.
- **One-off remediation** for hosts that drifted out of compliance
  with the central pipeline.

## When this is NOT the right method

- **Fleets > a few hundred hosts.** Move to Ansible / Puppet /
  Chef / Salt — they handle inventory drift, retries, and upgrade
  cycles much better than a one-shot script.
- **Air-gapped environments where outbound to the cluster is the
  problem.** Either pre-download the script and package together
  and ship over your air-gap channel, or use the internal repo
  method ([03](./03-package-repo-satellite.md)).

---

## See also

- [`01-manual-rpm-deb.md`](./01-manual-rpm-deb.md) — the manual baseline
- [`04-ansible.md`](./04-ansible.md) — fleet rollout via Ansible
- [`08-verification.md`](./08-verification.md) — confirm the install
- [`../operations/02-proxy-configuration.md`](../operations/02-proxy-configuration.md) — proxy configuration
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)
