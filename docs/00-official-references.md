# Official Cisco Documentation — Source of Truth

This repository is a **practitioner companion** to the official
Cisco Secure Workload (CSW) documentation. Anything authoritative
— exact installer flags for your release, the precise supported
OS / kernel matrix, supported NPCAP versions, agent service
names per major version, the cluster's default port set — comes
from Cisco's documentation portal, **not from this repo**.

When in doubt, the official docs win.

---

## Canonical links — CSW 4.0

| Source | Where to find it |
|---|---|
| **CSW 4.0 documentation landing page** | [`cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/landing-page/secureworkload-40-docs.html`](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/landing-page/secureworkload-40-docs.html) |
| **CSW User Guide — On-Premises, Release 4.0** | [`cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40.html`](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40.html) |
| **CSW User Guide — SaaS, Release 4.0** | [`cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-saas-v40.html`](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-saas-v40.html) |
| **Compatibility Matrix** (single page, all current releases) | [`cisco.com/c/m/en_us/products/security/secure-workload-compatibility-matrix.html`](https://www.cisco.com/c/m/en_us/products/security/secure-workload-compatibility-matrix.html) — supported OS / kernel / orchestrator / external-system versions per agent release; always cross-check this for your specific CSW version before any install |
| Release Notes | Documentation portal → CSW → your release → Release Notes |
| Cisco Secure Workload home | [`cisco.com/c/en/us/products/security/secure-workload/index.html`](https://www.cisco.com/c/en/us/products/security/secure-workload/index.html) |
| TAC support | [`cisco.com/c/en/us/support/index.html`](https://www.cisco.com/c/en/us/support/index.html) |

For releases other than 4.0, navigate to the same path and select
your release from the version drop-down.

---

## Software Agents — install pages (CSW 4.0 On-Prem)

The User Guide is split into chapters. The agent-install ones are
the most-cited references for this repo's runbooks; bookmark them.

| Chapter | URL |
|---|---|
| **Deploy Software Agents on Workloads** (overview, install methods, prerequisites, supported platforms) | [`.../deploy-software-agents.html`](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html) |
| **Install Linux Agents for Deep Visibility and Enforcement** | [`.../install-linux-agents-for-deep-visibility-and-enforcement.html`](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/install-linux-agents-for-deep-visibility-and-enforcement.html) |
| **Post-Installation Tasks and Details for Software Agents** (config files, service management, log locations, decommission) | [`.../post-installation-tasks-and-details-for-software-agents.html`](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/post-installation-tasks-and-details-for-software-agents.html) |
| **Network Flows / Traffic Visibility** (how flow observations are formed; quotas) | [`.../network-flows-traffic-visibility.html`](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/network-flows-traffic-visibility.html) |
| **Configuration Limits in Secure Workload** (flow event rate caps per appliance, scale guidance) | [`.../configuration-limits-in-secure-workload.html`](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configuration-limits-in-secure-workload.html) |

The Windows / Kubernetes / OpenShift / AIX / Solaris install
chapters live under the same parent path with analogous slugs
(e.g., `install-windows-agents-...`, `install-kubernetes-or-openshift-agents-...`).
Navigate from the User Guide root if a slug ever moves.

---

## Connectors — agentless flow ingestion and metadata sources

Connectors are how CSW gets data from sources that don't run a
host agent — network devices that export flow records, endpoints
managed via Cisco Secure Client / ISE, and the cloud / vCenter
control plane. Each connector runs as a Docker container on a
**Secure Workload Ingest Appliance**.

> **Master reference.** [Configure and Manage Connectors for
> Secure Workload (4.0 On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html)
> — single chapter covering every connector. Bookmark this; the
> per-connector subsections below all anchor inside it.

### Flow ingestion connectors

| Connector | What it ingests | When to use |
|---|---|---|
| **NetFlow** | NetFlow v9 / IPFIX from any compatible device | Generic agentless flow ingest — Catalyst 9000, Nexus 9000, ASR / ISR, third-party gear that exports NetFlow / IPFIX |
| **ERSPAN** | Encapsulated Remote SPAN (GRE-tunnelled mirror) | When the source device only supports port-mirroring (not native flow export) |
| **Cisco Secure Firewall** (ASA Connector) | NSEL records from ASA / FTD | Cisco Secure Firewall / FTD estate |
| **Meraki** | NetFlow v9 from Meraki MX | Meraki SD-WAN / branch firewalls |
| **F5** | F5 BIG-IP IPFIX | App-tier visibility behind an F5 |
| **NetScaler** | Citrix NetScaler AppFlow | Citrix-fronted apps |

This is the modern path for **workloads that can't run a CSW
agent** (network appliances, storage / SAN controllers, OT
systems, embedded medical / industrial devices). It replaces the
older "Hardware Sensor on a SPAN port" framing — same outcome,
much less physical / cabling overhead, and on the same connector
framework as everything below.

### Endpoint / identity connectors

| Connector | What it ingests | When to use |
|---|---|---|
| **AnyConnect** | Flow observations + inventory from Cisco Secure Client (formerly AnyConnect) endpoints with NVM enabled | Corporate laptops / desktops where Secure Client is already deployed |
| **ISE** (via pxGrid) | Endpoint identity, posture, profile metadata from Cisco ISE | Mixed-device estates (printers, IoT, OT, BYOD) where ISE is the source of identity truth |

See [`05-anyconnect-ise-alternatives.md`](./05-anyconnect-ise-alternatives.md)
for the operating model of both.

### Cloud and virtualisation connectors

| Connector | What it ingests | When to use |
|---|---|---|
| **AWS** | EC2 / ECS inventory + VPC Flow Logs | AWS accounts where you want broad visibility without per-VM agents |
| **Azure** | VM inventory + NSG Flow Logs | Azure subscriptions, same rationale |
| **GCP** | GCE inventory + VPC Flow Logs (also: backup / restore VPC firewall rules) | GCP projects, same rationale |
| **vCenter** | VM inventory, host / cluster / datastore metadata, vSphere tags | On-prem vSphere estates — see [`../agentless/04-vcenter-connector.md`](../agentless/04-vcenter-connector.md) |
| **Kubernetes** | Pod / Service / Namespace inventory directly from the K8s API | When you want CSW to know about K8s objects without running the agent DaemonSet (or in addition to it) |

See [`../agentless/`](../agentless/) for cloud / vCenter operating
patterns.

---

## What the official docs are authoritative for (and we are not)

This repository deliberately defers to the official docs on:

- **Exact installer script flags** — they change between releases.
  Always run `bash tetration_linux_installer.sh --help` (or the
  Windows / K8s equivalent) on the script generated by *your*
  cluster, and treat the script's `--help` output as the source
  of truth for the flag set in your release.
- **Supported OS, kernel, container runtime, K8s, NPCAP versions**
  — the Compatibility Matrix is updated continuously per release;
  this repo's snapshot tables are illustrative.
- **Default install paths, service names, registry keys** —
  validated against typical 4.0 practice; if a release-specific
  bump renames something (`tetd` → `tet-sensor` is one historical
  example), the User Guide reflects it first.
- **Cluster-side workflows** — generating the installer script,
  managing scopes, configuring Agent Profiles, switching from
  Visibility to Enforcement, configuring connectors, RBAC, and
  every other UI workflow.

---

## What this repository is authoritative for

- **Operating patterns** that aren't in any single Cisco doc:
  end-to-end Ansible / Puppet / Chef / Salt rollouts, Golden AMI
  / Compute Gallery / GCE custom-image pipelines, Helm-vs.-raw
  DaemonSet trade-offs, OpenShift SCC binding workflow, GitOps
  / Terraform integration, etc.
- **Decision matrices** that map your environment shape (on-prem
  vs. cloud, fleet size, automation tooling already in place) to
  the right installation method.
- **Phased rollout patterns** for going from sensor installed to
  policy enforced safely (Monitor → Simulate → Enforce).
- **Compliance evidence patterns** — what artefacts CSW produces
  per agent, where they live, and how to assemble them for an
  auditor (paired with the
  [`CSW-Compliance-Mapping`](https://github.com/chandrapati/CSW-Compliance-Mapping)
  repository).
- **Common gotchas, troubleshooting flowcharts, and operational
  experience** distilled from real customer engagements.

---

## CSW 4.0 specifics worth knowing up front

The items below are restated from the CSW 4.0 User Guides
because they are commonly misunderstood or missed. Read them
once before any install attempt.

### Pre-installation requirements

- **Privilege.** Installation and ongoing agent execution
  requires **root (Linux/Unix) or Administrator (Windows)**
  privileges.
- **Storage.** The agent and log files require **at least 1 GB**
  of storage on the host.
- **Security tooling exclusions.** Configure exclusions in any
  EDR / AV / HIDS that monitors the host so it does not block
  the agent install or the agent's running activity. Cisco
  publishes per-product guidance in the User Guide.
- **Network.** Agents register to the cluster using an
  activation key, and may need an HTTPS proxy. Configure these
  in the user configuration file before installation.
- **Firewall + TLS.** If a firewall is between the workload and
  the cluster, or the host firewall is enabled, configure
  appropriate policies. CSW agents use TLS to reach the
  cluster; **any other certificate sent to the agent will fail
  the connection** (no MITM tolerance — see
  [`../operations/02-proxy.md`](../operations/02-proxy.md)).

### Installer script — the canonical generation flow

For any platform: navigate to **Software Agents → Agent List**
in the CSW portal, choose the tenant, optionally assign labels,
optionally configure the HTTPS proxy, and choose an **Installer
expiration**:

| Expiration | Use it when |
|---|---|
| No expiration | The script will be re-used by the deployment tooling for many hosts over a long time |
| One time | A single host install where you want the strictest possible blast-radius limit |
| Time-bound (N days) | A POV / project window with a defined cut-off |
| Number of deployments (N installs) | Bulk roll-outs where you want a numeric cap on how many hosts the script can register |

Treat the generated script as a **secret** — it embeds the
activation key and (for on-prem clusters) the CA chain.

### Linux installer script flags (CSW 4.0)

```
bash tetration_linux_installer.sh [--pre-check] [--skip-pre-check=<option>]
  [--no-install] [--logfile=<filename>] [--proxy=<proxy_string>]
  [--no-proxy] [--help] [--version] [--sensor-version=<version_info>]
  [--ls] [--file=<filename>] [--save=<filename>] [--new] [--reinstall]
  [--unpriv-user] [--force-upgrade] [--upgrade-local]
  [--upgrade-by-uuid=<filename>] [--basedir=<basedir>]
  [--logbasedir=<logbdir>] [--tmpdir=<tmp_dir>] [--visibility]
  [--golden-image]
```

Practitioner cheat-sheet for the most-used flags:

| Flag | Use case |
|---|---|
| `--pre-check` | Validate prerequisites without installing — run first on the first host of any new estate |
| `--skip-pre-check=<option>` | Skip a specific pre-check (e.g., `all`); use only when you've validated separately |
| `--proxy=http://proxy.example.com:8080` | Force traffic via a forward proxy |
| `--no-proxy` | Force direct egress; explicit override of any inherited proxy env |
| `--visibility` | Install Visibility-only — no enforcement engaged at the kernel |
| `--golden-image` | Install but skip first-boot activation; for baking into AMI / Compute Gallery / VM template — pair with a first-boot script in the image |
| `--reinstall` | Wipe + reinstall on a host that already has the agent |
| `--force-upgrade` | Upgrade to the latest version even if the host is already on a supported version |
| `--upgrade-local` | Upgrade from a local package; don't pull from the cluster |
| `--unpriv-user` | Provision the agent's runtime user without elevated privileges (where supported) |
| `--basedir=<dir>` | Install to a non-default base directory (SELinux: see below) |
| `--sensor-version=<version_info>` | Pin a specific sensor version (e.g., to roll forward in waves) |

> **SELinux + custom base dir.** When the agent installs, it
> creates a special user `tet-sensor` on the host. If PAM or
> SELinux is configured, grant `tet-sensor` the appropriate
> privileges. If you use `--basedir=<dir>` to install somewhere
> non-standard and SELinux is enforcing, you must allow execute
> for that location (or relabel it) — otherwise the agent will
> install but fail to start.

### Windows agent — NPCAP and the golden-image trap

- The Windows TetSensor service binary is `tetsen.exe`.
- TetSensor captures network flows using **NPCAP**. Cisco
  ships the supported NPCAP version with the installer; running
  an unsupported NPCAP (or an incompatible NPCAP configuration)
  can cause unknown OS performance or stability issues. **Do
  not** swap NPCAP out on hosts that run TetSensor.
- **Critical golden-image / VM-template caveat.** When the
  Windows agent is installed on a VM template, NPCAP binds to
  the network stack at install time. **When a new VM is cloned
  from that template, the NPCAP binding does not carry forward
  cleanly** — NPCAP fails to capture on the cloned VM. There is
  no Windows equivalent of the Linux `--golden-image` flag at
  this writing; the official guidance is to install TetSensor
  on each cloned VM via a post-clone deployment step (SCCM,
  Intune, GPO startup script, or a first-boot PowerShell
  invocation of the CSW PowerShell installer) rather than
  baking it into the template.

### Kubernetes / OpenShift — what's actually in the install

For K8s and OpenShift, the installer script does not contain
the agent software itself. Instead:

- The script provisions namespaces, RBAC, the DaemonSet, and
  configuration.
- Each cluster node **pulls the agent Docker image from the
  Secure Workload cluster** at pod startup time.

This implies:

- Cluster nodes need image-pull connectivity to the CSW cluster
  (or to your internal registry mirror — see
  [`../kubernetes/01-daemonset-helm.md`](../kubernetes/01-daemonset-helm.md)).
- Air-gapped K8s requires the agent image mirrored to your
  internal registry and an `image.repository` override.

**Service mesh.** CSW provides comprehensive visibility and
enforcement for applications running in Kubernetes / OpenShift
clusters that have **Istio Service Mesh** enabled.

**Calico CNI.** CSW 4.0 supports Calico **3.13** with one of
the following Felix configurations:

- `ChainInsertMode: Append, IptablesRefreshInterval: 0`, or
- `ChainInsertMode: Insert, IptablesFilterAllowAction: Return,
  IptablesMangleAllowAction: Return, IptablesRefreshInterval: 0`

If your Calico version or Felix config differs, validate
behaviour with Cisco TAC before relying on CSW enforcement on
that cluster.

### Connections established by the agent

A software agent installed on a workload establishes **multiple
TLS connections** to the cluster across distinct channels:

| Channel | Purpose |
|---|---|
| WSS | Bidirectional control-plane channel (registration, configuration push) |
| Check-in | Periodic agent health / config fetch |
| Flow export | Telemetry stream for observed flows |
| Enforcement | Policy fetch + enforcement ack channel |

The exact connection count varies by sensor type (Visibility,
Enforcement, Kubernetes / OpenShift). Plan firewall and proxy
session limits with this in mind — connection-rate limits on
egress proxies are a common source of intermittent agent
disconnects.

### Policy enforcement — default state

By default, agents installed on workloads **have the capability
to enforce policy, but enforcement is disabled.** You explicitly
enable enforcement on selected hosts in the CSW UI when ready.
When the agent enforces a policy, it applies an ordered set of
rules (ALLOW or DROP) over the parameters of source,
destination, port, protocol, and direction.

The agent runs in a privileged domain — **as root on Linux, as
SYSTEM on Windows.**

### Supported platforms — CSW 4.0 SaaS

CSW 4.0 SaaS supports agents on:

- Linux (broad distribution coverage)
- Windows (server + client)
- AIX
- Solaris
- Kubernetes / OpenShift

Always cross-check the **Compatibility Matrix** for your CSW
release for the exact OS and kernel versions supported.

### When you don't need a CSW agent

Two important platform-specific cases where a CSW agent on the
endpoint is **not** required, because Cisco-side connectors
provide the equivalent telemetry:

- **AnyConnect Network Visibility Module (NVM).** Endpoints
  running Cisco AnyConnect Secure Mobility Client with NVM are
  registered with CSW via the AnyConnect connector, which
  exports flow observations, inventory, and labels. No CSW
  agent on the endpoint.
- **Cisco ISE.** Endpoints registered with Cisco ISE are
  surfaced to CSW via the ISE connector, which collects
  endpoint metadata from ISE through pxGrid. No CSW agent on
  the endpoint.

See [`./05-anyconnect-ise-alternatives.md`](./05-anyconnect-ise-alternatives.md)
for the operating model and decision criteria.

---

## How this repo cites the official docs

Every per-method runbook in this repository ends with a **See
also** block that points back to:

- The relevant section of the CSW User Guide
- This document (`docs/00-official-references.md`)
- The companion repos
  [`CSW-Compliance-Mapping`](https://github.com/chandrapati/CSW-Compliance-Mapping)
  and
  [`CSW-Tenant-Insights`](https://github.com/chandrapati/CSW-Tenant-Insights)

If a runbook in this repo contradicts the User Guide for your
specific release, **the User Guide wins**. Open an issue on this
repo so the practitioner content can be updated.
