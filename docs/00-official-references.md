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
  this repo follows what Cisco documents for **CSW 4.0**: the
  Linux systemd unit is **`csw-agent`**, the Windows service is
  **`CswAgent`** (display name *Cisco Secure Workload Deep
  Visibility*), and Cisco-documented per-platform install
  directories are `/usr/local/tet`, `/opt/cisco/tetration`,
  `/var/opt/cisco/secure-workload`,
  `C:\Program Files\Cisco Tetration`, and
  `/opt/cisco/secure-workload`. Earlier Tetration releases used
  different naming — the User Guide for *your* release is the
  authoritative source.
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

### Windows agent — service, flow capture, and the documented VDI / golden-image flow

> **Authoritative source.** The Windows agent details below are
> direct from Cisco's
> [Install Windows Agents for Deep Visibility and Enforcement](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
> chapter (Verify Windows Agent Installation, Deploying Agents on
> a VDI Instance or VM Template, and Windows Agent Flow Captures
> sections).

- **Service name.** The Windows service is **`CswAgent`** (case
  varies in the docs: `CswAgent`, `cswagent`). Display name:
  *Cisco Secure Workload Deep Visibility*. Verify with
  `sc.exe query CswAgent` or `services.msc`.
- **Install path.** `C:\Program Files\Cisco Tetration` by
  default; configurable via the `-installFolder` PowerShell flag
  or the `installfolder=` MSI option.
- **Process names** (per Cisco's *Security Exclusions* table,
  Table 4): `CswEngine.exe` and `TetEnfC.exe`.
- **Flow capture driver.**
  - **Windows Server 2008 R2 (and pre-3.8 agents):** uses
    **Npcap**. Cisco ships the supported Npcap version with the
    installer; if an older Npcap is already present, pass
    `overwritenpcap=yes` (MSI) or `-npcap` (PowerShell) to upgrade
    it. See the *Windows Agent Installer and Npcap—For Windows
    2008 R2* subsection of Cisco's chapter for the exact
    install / upgrade / uninstall behaviour.
  - **All other Windows OS, agent 3.8+:** uses Microsoft's
    in-built **`ndiscap.sys`** driver via Event Tracing for
    Windows (ETW). Sessions are named `CSW_MonNet` and
    `CSW_MonDns`. Per Cisco's chapter, "the agent installer
    uninstalls Npcap if [it was] installed by the agent and is
    not in use" once the host is on agent 3.8+. **You generally
    should not be touching Npcap on modern Windows installs.**
- **VDI / VM template / golden-image flow — documented and
  supported.** Cisco's *Deploying Agents on a VDI Instance or VM
  Template (Windows)* section walks through the supported flow:
  - **PowerShell installer:** pass **`-goldenImage`**. Per Cisco:
    *"install Cisco Secure Workload Agent but do not start the
    Cisco Secure Workload Services; use to install Cisco Secure
    Workload Agent on Golden Images in VDI environment or
    Template VM. On VDI/VM instance created from golden image
    with different host name, Cisco Secure Workload Services
    will work normally."*
  - **MSI installer:** pass **`nostart=yes`**. Per Cisco:
    *"Pass this parameter, when installing the agent using a
    golden image in a VDI environment or VM template, to prevent
    agent service — CswAgent from starting automatically. On VDI
    / VM instances created using the golden image and with a
    different host name, these services, as expected, start
    automatically."*
  - **Npcap on the golden image.** Per Cisco: *"Agent will not
    install Npcap on golden VMs, but will be automatically
    installed if needed on VM instances cloned from a golden
    image."* This means the Npcap-on-golden-image concern that
    earlier Tetration documentation called out is **handled by
    the documented `-goldenImage` / `nostart=yes` flow** — Npcap
    installs after the clone, when the host name is final.
  - **Constraint.** Do not change the host name of the golden
    image / VM template after installing the agent. If you do,
    Cisco directs you to delete the agent registration via
    OpenAPI before re-cloning.

> **Linux equivalent.** The Linux installer's **`--golden-image`**
> flag plays the same role for VDI / VM-template builds on Linux
> hosts: install but don't start; services start normally on
> instances cloned with a different host name.

### Kubernetes / OpenShift — what's actually in the install

> **Authoritative source.** Cisco's
> [Install Kubernetes or OpenShift Agents for Deep Visibility and Enforcement](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
> section.

**Cisco's documented K8s / OpenShift install method is the
Agent Script Installer.** The CSW UI's *Manage → Workloads →
Agents → Installer → Agent Script Installer* generates a Linux
shell script that, when run on a workstation with `kubectl`
admin context against the cluster, provisions:

- The `tetration` namespace ("Secure Workload entities are
  created in the `tetration` namespace" — Cisco's exact wording).
- Service accounts, RBAC, and the DaemonSet.
- A configuration that points the agent pods at the CSW cluster.

The script itself does **not** contain the agent software.
Each cluster node **pulls the agent container image from the
Secure Workload cluster** at pod startup time. Per Cisco:
*"The HTTP Proxy configured on the agent installer page prior
to download only controls how Secure Workload agents connect to
the Secure Workload cluster. This setting does not affect how
Docker images are fetched by Kubernetes or OpenShift nodes,
because the container runtime on those nodes uses its own proxy
configuration."*

**This implies:**

- Cluster nodes need image-pull connectivity to the CSW cluster
  on `CFG-SERVER-IP:443` (or to your internal registry mirror).
- Air-gapped K8s requires the agent image mirrored to your
  internal registry and the matching container-runtime
  registry / proxy config (Cisco's chapter walks through
  `containerd` `config.toml` adjustments for this).

> **About Helm charts.** Cisco's CSW 4.0 *Deploy Software
> Agents on Workloads* chapter does **not** publish or document
> a Helm chart for the K8s / OpenShift agent — the
> agent-script-installer flow above is the documented path. Some
> shops maintain their own Helm chart wrapping the same
> DaemonSet shape; if your shop uses Helm internally that's a
> reasonable practice, but treat
> [`../kubernetes/01-daemonset-helm.md`](../kubernetes/01-daemonset-helm.md)
> as a community pattern, not a Cisco-published artefact.
> Always confirm chart name, registry, and image tag against
> *your* tooling rather than against this repo.

**Service mesh — Istio.** Cisco's chapter explicitly documents
visibility and enforcement for applications running in K8s /
OpenShift clusters with **Istio Service Mesh** enabled, and
publishes the sidecar / control-plane port list to include in
your segmentation policies. The default Envoy sidecar ports are
**15000, 15001, 15004, 15006, 15008, 15020, 15021, 15053,
15090**; the Istio control-plane ports are **443, 8080, 15010,
15012, 15014, 15017** (per Cisco's
*Deep Visibility and Enforcement with Istio Service Mesh*
section). If your Istio deployment overrides these defaults,
follow your `istio` global config.

**CNI — Calico.** Per Cisco's *Requirements for Policy
Enforcement* in the K8s section: *"The following CNI plug-ins
are tested for the above requirements: **Calico (3.13)**"* with
one of:

- `ChainInsertMode: Append, IptablesRefreshInterval: 0`, or
- `ChainInsertMode: Insert, IptablesFilterAllowAction: Return,
  IptablesMangleAllowAction: Return, IptablesRefreshInterval: 0`

Cisco lists the **two requirements** that any CNI must meet for
CSW enforcement to function: *"Provide flat address space (IP
network) between all nodes and pods. Network plug-ins that
masquerade the source pod IP for intracluster communication are
not supported. Not interfere with Linux iptables rules or marks
that are used by the Secure Workload Enforcement Agent (mark
bits 21 and 20 are used to allow and deny traffic for NodePort
services)."* Other CNIs may meet those two requirements but are
**not formally tested by Cisco** in the 4.0 chapter — validate
with TAC before relying on CSW enforcement on a cluster running
a CNI other than Calico 3.13.

**Other K8s constraints from Cisco's chapter:**

- Privileged pods must be permitted by the cluster's
  PodSecurity / PSP / SCC policy.
- `busybox:1.33` images must be preinstalled or pullable from
  Docker Hub.
- For Windows worker nodes (CSW agent supports Windows nodes
  on Kubernetes 1.27+ with `containerd` runtime, on Windows
  Server 2019 / 2022 per the chapter), the
  `mcr.microsoft.com/oss/kubernetes/windows-host-process-containers-base-image:v1.0.0`
  image must be preinstalled or pullable.
- IPVS-based `kube-proxy` mode is **not** supported for
  OpenShift.
- Agents on K8s should be configured with **Preserve Rules
  enabled** in the Agent Config profile.

### Connections established by the agent

A software agent installed on a workload establishes **multiple
TLS connections** to the cluster across distinct channels:

| Channel | Purpose |
|---|---|
| WSS | Bidirectional control-plane channel (registration, configuration push) |
| Check-in | Periodic agent health / config fetch |
| Flow export | Telemetry stream for observed flows |
| Enforcement | Policy fetch + enforcement ack channel |

**Per-context ports** — direct from Cisco's
[Connectivity Information](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
table (Table 2 in the chapter):

| Agent type | Config server | Collectors | Enforcement back-end |
|---|---|---|---|
| Visibility (on-premises) | `CFG-SERVER-IP:443` | `COLLECTOR-IP:5640` | n/a |
| Visibility (SaaS) | `CFG-SERVER-IP:443` | `COLLECTOR-IP:443` | n/a |
| Enforcement (on-premises) | `CFG-SERVER-IP:443` | `COLLECTOR-IP:5640` | `ENFORCER-IP:5660` |
| Enforcement (SaaS) | `CFG-SERVER-IP:443` | `COLLECTOR-IP:443` | `ENFORCER-IP:443` |
| Docker image fetch (Kubernetes / OpenShift) | `CFG-SERVER-IP:443` | n/a | n/a |

> Per Cisco: *"Deep visibility and enforcement agents connect to
> all available collectors. The enforcement agent connects to
> only one of the available endpoints."* Find the config-server
> IP at *Platform → Cluster Configuration → Sensor VIP*; find
> the collectors / enforcer IPs under *External IPs* on the
> same page.
>
> *"The Secure Workload agent always acts as a client to
> initiate the connections to the services hosted within the
> cluster, and never opens a connection as a server."* — i.e.
> no inbound permit is required from the cluster to the agent
> host. An agent can be located behind NAT.

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

### Supported platforms — CSW 4.0

Per Cisco's chapter intro: *"This chapter describes the
deployment and management of Cisco Secure Workload software
agents on various operating systems and environments, such as
**Linux, Windows, Kubernetes, and AIX**."* The chapter also has
a dedicated *Install Solaris Agents for Deep Visibility and
Enforcement* section (Solaris 10 and 11.4). Per-platform
sub-sections in the chapter:

- *Install Linux Agents for Deep Visibility and Enforcement*
- *Install Windows Agents for Deep Visibility and Enforcement*
- *Install AIX Agents for Deep Visibility and Enforcement*
- *Install Kubernetes or OpenShift Agents for Deep Visibility
  and Enforcement*
- *Install Solaris Agents for Deep Visibility and Enforcement*

For exact supported OS / kernel versions, the chapter directs
you to: (1) **Release Notes** for your specific CSW version,
(2) the **Agent Install Wizard** in your cluster's UI under
*Manage → Workloads → Agents → Installer* (which lists supported
versions for the selected platform / agent type), and (3) the
**Support Matrix** at
[`cisco.com/go/secure-workload/requirements/agents`](https://www.cisco.com/go/secure-workload/requirements/agents)
or the public
[Compatibility Matrix](https://www.cisco.com/c/m/en_us/products/security/secure-workload-compatibility-matrix.html).

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
