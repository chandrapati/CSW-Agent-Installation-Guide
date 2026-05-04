# Prerequisites — Read This First

Almost every failed CSW agent installation traces back to one of
five issues:

1. A closed firewall port between the workload and the CSW cluster
2. A TLS trust gap (the workload doesn't trust the CSW cluster cert)
3. An unsupported OS or kernel version
4. A clock-skew problem (NTP not configured; certs reject)
5. The activation key / sensor type / scope target was wrong

Get these five right before any install attempt and the rest of
this guide goes smoothly.

> **Official source.** The authoritative pre-install requirements
> for your release are in the *Cisco Secure Workload User Guide*
> for your edition (On-Premises 4.0 or SaaS 4.0) — see
> [`00-official-references.md`](./00-official-references.md).
> The five items below restate (and operationalise) the official
> pre-install checklist for CSW 4.0.

---

## 0. CSW 4.0 — official pre-install requirements

Restated from the CSW 4.0 User Guide (On-Prem and SaaS):

- **Privilege.** Installing and running the agent service requires
  **root (Linux/Unix) or Administrator (Windows)** privileges.
  Non-root install paths exist for some sensor types via the
  `--unpriv-user` installer flag — review your release's User
  Guide before relying on them.
- **Storage.** Reserve **at least 1 GB** for the agent and its
  log files on each host.
- **Security tooling exclusions.** EDR / AV / HIDS products that
  monitor the host can block agent install or block agent
  activity at runtime. **Configure exclusions** in those tools
  *before* installing — the User Guide lists per-product
  guidance (Defender, CrowdStrike, Symantec, etc.).
- **Activation key + optional HTTPS proxy.** Agents register
  using an activation key generated in the CSW UI; if the
  workload egresses through a proxy, configure the proxy in the
  user configuration file before install.
- **Firewall + TLS.** If a firewall sits between the workload and
  the cluster (or the host firewall is enabled), open the
  required policy. CSW agents use TLS to reach the cluster, and
  **any other certificate sent to the agent will fail the
  connection** — TLS-decrypting proxies must be configured to
  bypass the cluster FQDN. See
  [`../operations/02-proxy.md`](../operations/02-proxy.md).

---

## 1. Network prerequisites

### Required outbound connectivity

The host agent (any sensor type) needs outbound TCP connectivity to
the CSW cluster. Default ports:

| Direction | Source | Destination | Port | Purpose |
|---|---|---|---|---|
| Outbound | Each workload | CSW collector VIP | 443/TCP | Sensor → cluster: registration, telemetry upload, policy fetch, software updates |
| Outbound | Each workload | CSW NTP source (cluster or org NTP) | 123/UDP | Time sync (clock skew breaks TLS) |
| Outbound | Each workload | DNS resolver | 53/UDP, 53/TCP | Resolve cluster hostname |

For SaaS clusters (Cisco-hosted) the destination is a public
hostname; for on-prem clusters it's typically the **collector VIP**
exposed on a dedicated cluster interface. Check the CSW UI under
*Manage → Agents → Install Agent* — the install screen always
shows the exact destination your cluster expects.

### Common firewall gotchas

- **East-west firewalls between the workload subnet and the cluster
  subnet** — security teams often forget that even an "internal"
  on-prem cluster needs an east-west exception.
- **Egress proxies that intercept TLS** — the proxy must be
  configured to pass-through the cluster cert. CSW agents will
  not trust an MITM cert; **add the cluster FQDN to the proxy's
  bypass list**. See
  [`../operations/02-proxy.md`](../operations/02-proxy.md).
- **Cloud egress NAT gateways** — outbound 443 generally works, but
  some FedRAMP / regulated subnets block by default. Validate with
  `curl -v https://<cluster-vip>:443/` from the workload.
- **Cluster has multiple collector VIPs (HA)** — open egress to all
  of them, not just the first one returned by DNS.

Full port reference, including optional ports for advanced features,
in [`../operations/01-network-prereq.md`](../operations/01-network-prereq.md).

### Sensor → cluster TLS

The agent validates the cluster's TLS certificate using the CA
chain bundled in the agent installer. For on-prem clusters that use
an internal CA:

- The CSW-generated installer (the most common method) **embeds
  the cluster CA chain automatically**. This is why the CSW shell
  script / PowerShell script approach is preferred over a vendor
  package and a separate config step.
- For manual RPM/DEB/MSI installs, you may need to deposit the CA
  chain in `/etc/tetration/ca.pem` (Linux) or
  `%PROGRAMDATA%\Cisco\Tetration\conf\ca.pem` (Windows) per the
  install guide. The CSW *Manage → Agents* UI shows the exact
  filename and location for your cluster.

If TLS handshake fails, the agent log will say so explicitly:

```
[ERROR] tls handshake failed: x509: certificate signed by unknown authority
```

Fix path: confirm `ca.pem` is present and matches the cluster CA;
restart the agent service.

---

## 2. Operating system support

CSW publishes a formal [**Compatibility Matrix**](https://www.cisco.com/c/m/en_us/products/security/secure-workload-compatibility-matrix.html)
in the Cisco Secure Workload documentation portal — a single page
covering all current agent releases — that lists exact supported
OS and kernel versions per CSW release alongside supported
external systems (AnyConnect, ISE, vCenter, Kubernetes, OpenShift,
Secure Firewall, etc.). Always check the matrix for your specific
CSW version before any install. The list below is the
typical-currency snapshot for context; treat it as illustrative.

### Linux — Deep Visibility / Enforcement (the common sensor types)

| Distribution | Typical supported versions |
|---|---|
| Red Hat Enterprise Linux (RHEL) | 7.x, 8.x, 9.x |
| CentOS | 7.x (Stream), 8.x (Stream) |
| Rocky Linux | 8.x, 9.x |
| AlmaLinux | 8.x, 9.x |
| Oracle Linux | 7.x, 8.x, 9.x (RHCK and UEK kernels) |
| Ubuntu | 18.04 LTS, 20.04 LTS, 22.04 LTS, 24.04 LTS |
| Debian | 10, 11, 12 |
| SUSE Linux Enterprise Server (SLES) | 12 SPx, 15 SPx |
| Amazon Linux | 2, 2023 |

**Kernel-locked.** The Deep Visibility / Enforcement sensor compiles
a small kernel module and is therefore tied to specific kernel
versions per CSW release. After kernel updates on the workload, the
agent may degrade until either the kernel is rolled back, the agent
is upgraded to a release that supports the new kernel, or the
workload is moved to Universal Visibility.

### Linux — Universal Visibility (UV) — broader OS support

For OS / kernel combinations that the Deep agent does not yet
support, Universal Visibility runs in user space and supports a
broader matrix:

- Older Linux versions
- ARM64 platforms
- Some embedded or specialised Linux distributions

UV provides flow telemetry and process inventory but **not
enforcement**. Deep visibility into kernel-level events is reduced.
Use UV when "any visibility is better than none".

### Windows

| Distribution | Typical supported versions |
|---|---|
| Windows Server | 2012 R2, 2016, 2019, 2022, 2025 |
| Windows Client | Windows 10, Windows 11 (where the platform team allows running a server-class agent on client OS) |

For laptops / desktops in a user-endpoint role, **a CSW agent
is not required** if either of the following is in place:

- The endpoint runs **Cisco AnyConnect Secure Mobility Client
  with the Network Visibility Module (NVM)** — registered to CSW
  via the AnyConnect connector.
- The endpoint is registered with **Cisco ISE** — surfaced to
  CSW via the ISE connector through pxGrid.

See [`./05-anyconnect-ise-alternatives.md`](./05-anyconnect-ise-alternatives.md)
for the operating model.

### Containers

The CSW agent runs at the **node** level on Kubernetes (DaemonSet),
not in each pod. Container runtime and Kubernetes distribution
support:

- Kubernetes 1.24+
- Docker, containerd, CRI-O
- EKS, AKS, GKE, OpenShift, Rancher / RKE, plain kubeadm

See [`kubernetes/`](../kubernetes/) for distribution-specific notes.

### AIX and Solaris

CSW 4.0 SaaS supports agents on **AIX** and **Solaris** in
addition to Linux, Windows, and Kubernetes / OpenShift. The
exact AIX / Solaris versions and the supported sensor-type
combinations are release-specific — confirm against the CSW
4.0 User Guide and the Compatibility Matrix before committing
those platforms to the deployment plan.

### Mainframe and other niche platforms

For platforms not on the Compatibility Matrix at all, the
options are:

- **NetFlow / ERSPAN ingestion** via the matching Secure Workload
  connector (no agent on the workload — the network device's own
  NetFlow / IPFIX / NSEL export, or an ERSPAN session, lands on a
  Secure Workload Ingest Appliance). See the
  [Connectors chapter on docs.cisco.com](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html)
  and [`02-sensor-types.md` § 5](./02-sensor-types.md).
- **Cloud / virtualisation Connector** (inventory + flow log
  tier; no per-workload agent)

Engage your Cisco SE / TAC channel for anything beyond the
matrix.

---

## 3. Resource sizing

The agent is intentionally lightweight. Typical steady-state
footprint per workload:

| Resource | Typical |
|---|---|
| CPU | < 2 % of one core |
| Memory | 200–500 MB |
| Disk | ~1 GB install footprint + small log + cache directory |
| Network | A few KB/s under steady state, bursts during initial registration and during ADM pulls |

**Caveats:**

- **CPU spike during initial software inventory** — the first
  package walk on a host with many installed packages can run a
  few minutes at higher CPU. This subsides once the inventory is
  cached and only delta updates are reported.
- **Memory growth on hosts with very high flow rates** — extreme
  flow generators (load balancers, proxy hosts) may need a
  per-workload exception via the CSW agent profile UI. See the
  troubleshooting doc.
- **Don't run the agent on appliances with strict change-control**
  — many SAN/storage appliances, network controllers, and OT
  gateways forbid third-party agents. Use **NetFlow / ERSPAN
  ingestion** via the matching Secure Workload connector for
  those (see [`02-sensor-types.md` § 5](./02-sensor-types.md)).

---

## 4. Time synchronisation (NTP)

Cluster TLS validation requires a workload clock within a few
seconds of the cluster's clock. NTP requirements:

- Workload synchronises to a reachable NTP source (org NTP, cloud
  provider time service, or the CSW cluster's NTP).
- Drift > 5 minutes will typically cause TLS validation to fail
  with `x509: certificate has expired or is not yet valid`.
- For Windows: confirm `w32time` is configured to a reliable
  domain time source.
- For Linux: `chronyd` or `ntpd` running and synchronised
  (`chronyc tracking` shows recent sync).

---

## 5. CSW cluster prerequisites (what to have ready)

Before you install on the first workload, have the following from
the CSW cluster team:

| Item | Where to get it | Why |
|---|---|---|
| Cluster collector VIP / SaaS hostname | CSW *Manage → Agents → Install Agent* | The destination the agent must reach |
| Activation key / installer token | CSW *Manage → Agents → Install Agent* | Embedded in the CSW-generated installer; otherwise required as a flag |
| Target scope / VRF | CSW *Organize → Scopes* | Determines policy workspace membership and label inheritance |
| Sensor type per workload class | This guide → [`docs/02-sensor-types.md`](./02-sensor-types.md) | Deep Visibility vs. Enforcement vs. UV |
| CA chain (on-prem clusters) | CSW UI download | Required for TLS validation on manual installs |
| Proxy URL + auth (if applicable) | Network team | Required for hosts that egress through a proxy |

---

## 6. Pre-install checklist (one-page summary)

```
[ ] Outbound 443/TCP from workload → CSW collector VIP (HA: all of them)
[ ] Outbound 53/UDP and 123/UDP for DNS and NTP
[ ] OS + kernel on the CSW Compatibility Matrix for your target release
[ ] Workload clock synchronised to a reachable NTP source
[ ] CA chain available for on-prem cluster (CSW-generated installer embeds it)
[ ] Activation key / installer token from CSW Manage → Agents
[ ] Target scope decided in CSW UI
[ ] Sensor type decided (Deep Visibility / Enforcement / UV)
[ ] First-deployment plan: Monitoring mode for ≥30 days before Enforce
[ ] Change ticket open if your environment requires one
```

When all ten boxes are ticked, proceed to the OS-specific install
runbook.

---

## See also

- [`00-official-references.md`](./00-official-references.md) — CSW 4.0 official-doc cross-reference (read first)
- [`02-sensor-types.md`](./02-sensor-types.md) — pick the right sensor
- [`03-decision-matrix.md`](./03-decision-matrix.md) — pick the right install method
- [`04-rollout-strategy.md`](./04-rollout-strategy.md) — phased Monitor → Simulate → Enforce
- [`05-anyconnect-ise-alternatives.md`](./05-anyconnect-ise-alternatives.md) — when no CSW agent is needed
- [`../operations/01-network-prereq.md`](../operations/01-network-prereq.md) — exhaustive port and cert reference
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md) — when something goes wrong
