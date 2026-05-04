# Sensor Types — Pick the Right One

CSW ships several sensor flavours. Each fits a different workload
profile. This doc walks through all six and ends with a one-page
decision table.

> **Official sources.** Sensor type definitions and exact
> per-platform support are in the *Cisco Secure Workload User
> Guide* — see [`00-official-references.md`](./00-official-references.md).
> CSW 4.0 SaaS supports agents on Linux, Windows, AIX, Solaris,
> and Kubernetes / OpenShift platforms. Always cross-check the
> Compatibility Matrix for your release.
>
> Two pages on docs.cisco.com are the canonical references for
> what's covered below:
>
> - [Deploy Software Agents on Workloads (4.0 On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
>   — for the agent-based sensor types (Deep Visibility,
>   Enforcement, Universal Visibility).
> - [Configure and Manage Connectors for Secure Workload (4.0 On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html)
>   — for the agentless flow-ingest paths (NetFlow, ERSPAN,
>   AnyConnect, ISE, F5, NetScaler, Meraki, Secure Firewall, AWS,
>   Azure, GCP, vCenter).

---

## At a glance

| Sensor type | Telemetry | Enforcement | Where it runs | How it's installed |
|---|---|---|---|---|
| **Deep Visibility** | Flow + process + software inventory + vulnerability lookup | No (visibility only) | Linux, Windows host | `tet-sensor` package; `tetd` service |
| **Enforcement** | Everything Deep Visibility produces | **Yes** — workload-side firewall | Linux, Windows host | `tet-sensor-enforcer` package (or feature flag depending on release); `tetd` + `tet-enforcer` services |
| **Universal Visibility (UV)** | Flow + lighter process telemetry | No | Broader OS / kernel / arch coverage | `tet-sensor` (UV variant); user-space only |
| **AnyConnect NVM** | Endpoint flow telemetry from user devices | No (CSW-side; endpoint may be controlled by Cisco Secure Client) | macOS, Windows, Linux laptops via Cisco Secure Client | NVM module of Cisco Secure Client |
| **NetFlow / ERSPAN ingestion** | Flow records exported by the network device (NetFlow v9 / IPFIX / ERSPAN / NSEL) | No | Connector running on a Secure Workload **Ingest Appliance**; **no agent on the workload itself** | Network device exports flows → connector receives → CSW cluster. See [Connectors](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html). |
| **Cloud Sensor / Cloud Connector** | Inventory + flow logs via cloud APIs | No | Runs *in CSW* (or on an Ingest Appliance), polling AWS / Azure / GCP / vCenter; **no agent on the workload** | CSW *External Orchestrators / Connectors* configuration |

The first two — **Deep Visibility** and **Enforcement** — cover the
overwhelming majority of customer fleets. The other four are for
specific situations where the Deep / Enforcement agent is either
not supported or not allowed.

---

## 1. Deep Visibility (the default)

**What it does.** Captures every network flow, every process spawn,
every software-package change, and every kernel-level event of
interest, and forwards a structured stream to the CSW cluster. Also
runs vulnerability lookup against the installed package list and
returns CVE context per workload.

**What it doesn't do.** It does **not** enforce policy at the host
firewall — the workload's existing firewall (iptables / nftables /
Windows Filtering Platform) is unchanged. Use it for visibility,
ADM, and policy authoring. Promote to Enforcement only when you're
ready to enforce.

**OS support.** All current x86_64 Linux distributions on Cisco's
Compatibility Matrix; Windows Server 2012 R2 through current.

**When to use.**
- You want to see who is talking to whom and which processes are
  initiating it.
- You want continuous CVE inventory per workload with reachability
  context.
- You're in the build phase of a CSW deployment and policy is
  still being designed.

**When NOT to use.**
- The workload's OS or kernel isn't on the matrix → use
  Universal Visibility instead.
- The workload type forbids third-party agents → use **NetFlow /
  ERSPAN ingestion** (network-device-exported flows landing on a
  Secure Workload Ingest Appliance) or a **Cloud Connector**
  instead. See section 5 below.

---

## 2. Enforcement (Deep Visibility + workload firewall)

**What it does.** Everything Deep Visibility does, **plus** it
applies CSW-managed firewall rules at the workload kernel
(iptables / nftables on Linux; WFP on Windows). The CSW cluster
becomes the policy decision point; the agent becomes the policy
enforcement point.

**What it doesn't do.** Replace your network firewall. CSW
enforcement is the *workload-tier* control; you still need
perimeter and segment-level firewalls for everything outside the
agent's scope.

**OS support.** Same as Deep Visibility for current releases. Some
older OS versions support Deep Visibility but not Enforcement —
check the matrix.

**When to use.**
- After 30+ days of Deep Visibility, with policy authored in CSW
  workspaces and run in **Simulation** for at least one operational
  cycle (typically 2–4 weeks).
- When the workload is in scope for a control that requires
  workload-level least-privilege (HIPAA, PCI, NIST AC-3, CSF
  PR.IR-01, etc.).

**When NOT to use.**
- Day-one of any deployment. Always start with Deep Visibility.
- Workloads where the change ticket can't get approved for a
  workload-side firewall change. Stay in Deep Visibility on those
  hosts and rely on network-tier enforcement.

**Operational note.** By default, agents installed on workloads
**have the capability to enforce policy, but enforcement is
disabled.** You explicitly enable enforcement on selected hosts
in the CSW UI (*Manage → Agent Configuration*). The agent binary
is the same; what changes is the cluster-side instruction to
engage the enforcer module. The agent itself runs in a privileged
domain — **as root on Linux, as SYSTEM on Windows.** See
[`../operations/07-enforcement-rollout.md`](../operations/07-enforcement-rollout.md).

---

## 3. Universal Visibility (UV) — broader OS coverage

**What it does.** Lighter-weight flow telemetry and process
inventory, in user space only. No kernel module, no enforcement.

**Why it exists.** The Deep agent's kernel module is tied to
specific OS / kernel combinations. UV widens the net to:

- Older Linux (RHEL 5/6 era) where the Deep module isn't built
- ARM64 Linux
- Some specialised distros / niche kernels
- **AIX and Solaris** — supported in CSW 4.0 SaaS (per the
  Compatibility Matrix for your specific AIX / Solaris version)

**Trade-offs vs. Deep Visibility.**

| Capability | Deep Visibility | Universal Visibility |
|---|---|---|
| Flow telemetry | ✓ (kernel-level) | ✓ (user-space; comparable for most flows) |
| Process attribution | ✓ | ✓ (lighter detail) |
| Software inventory | ✓ | ✓ |
| Vulnerability lookup | ✓ | ✓ |
| Kernel-level event detection | ✓ | partial |
| Policy enforcement | ✓ (with Enforcement profile) | **No** |
| Forensic depth | high | moderate |

**When to use.**
- Workload OS / kernel not supported by Deep Visibility in your
  current CSW release.
- Customer mandate: zero kernel modules.

**When NOT to use.**
- Workload qualifies for Deep Visibility — always prefer Deep when
  the platform supports it.

---

## 4. AnyConnect Network Visibility Module (NVM)

**What it does.** Endpoint flow telemetry from user devices
(laptops / desktops). Delivered via **Cisco Secure Client** (the
product formerly known as AnyConnect) — the NVM module sits
alongside the VPN client and ships flow records per the IPFIX-style
NVM specification.

> **Important.** When NVM is in use, **no CSW agent is required
> on the endpoint** — the AnyConnect connector in CSW registers
> the endpoint and ingests flow observations, inventory, and
> labels directly from NVM. Same applies to endpoints registered
> with **Cisco ISE**, where the ISE connector via pxGrid takes
> the place of an endpoint agent. See
> [`05-anyconnect-ise-alternatives.md`](./05-anyconnect-ise-alternatives.md).

**Why it's separate.** User-endpoint visibility has a different
operational model than server-class visibility:

- Endpoints are typically not always-on; the NVM agent buffers and
  sends when connectivity is available.
- Endpoints typically don't enforce CSW-authored micro-segmentation
  policy; the policy decision point lives elsewhere (DUO / ZTNA /
  MDM stack).
- The user-endpoint privacy model is different; some org policies
  treat per-process telemetry on a corporate laptop differently
  than on a server.

**When to use.**
- You want flow visibility from corporate laptops in addition to
  servers.
- You already deploy Cisco Secure Client to those laptops.

**When NOT to use.**
- You only care about server-class workloads.
- Cisco Secure Client isn't part of your endpoint strategy.

**Where to deploy from.** MDM (Intune, Workspace ONE, Jamf for
macOS) is the standard delivery channel. NVM is a sub-feature of
Secure Client — enabled at install time via the Secure Client
profile.

---

## 5. NetFlow / ERSPAN ingestion (agentless flow for non-agent workloads)

**What it does.** For workloads that can't run a CSW host agent,
CSW ingests **flow records exported by the network device** rather
than instrumenting the workload itself. The network device (Catalyst
/ Nexus switch, ASR / ISR router, ASA / FTD firewall, Meraki MX, F5
BIG-IP, Citrix NetScaler, etc.) exports flows in a standard format
— NetFlow v9, IPFIX, ERSPAN, or NSEL — to a **Secure Workload
Ingest Appliance** in your DC. The matching **connector** running
on that appliance receives the flow records, processes them, and
reports flow observations to the CSW cluster.

> **Official source.** [Configure and Manage Connectors for
> Secure Workload (4.0 On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html).
> The same chapter exists in the SaaS user guide. The connector
> configuration UI in CSW lives at *Manage → External
> Orchestrators / Connectors*.

**Connectors available for flow ingestion (CSW 4.0).** All run as
Docker containers on a Secure Workload Ingest Appliance:

| Connector | Source format | Use it for |
|---|---|---|
| **NetFlow** | NetFlow v9 / IPFIX | Generic flow ingest from any device that can export NetFlow / IPFIX |
| **ERSPAN** | Encapsulated Remote SPAN (GRE-tunnelled mirror) | When the device can mirror traffic but doesn't export NetFlow; close to the old "tap a SPAN port" model |
| **Cisco Secure Firewall** (formerly ASA Connector) | NetFlow Secure Event Logging (NSEL) from ASA / FTD | Cisco Secure Firewall estate |
| **Meraki** | NetFlow v9 from Meraki MX | Meraki SD-WAN / branch firewalls |
| **F5** | F5 BIG-IP IPFIX | Application-tier visibility behind an F5 |
| **NetScaler** | Citrix NetScaler AppFlow | Citrix-fronted apps |

**Why this matters.** Some workload classes forbid CSW host agents:

- Network appliances (load balancers, firewalls, controllers,
  WAN-optimisers)
- Storage / SAN / NAS controllers
- OT systems (PLCs, RTUs, IEDs, HMIs) — never deploy a server
  agent on these; pair this approach with OT-aware monitoring
  (Cisco Cyber Vision, Claroty, Nozomi, Dragos)
- Embedded medical / industrial devices
- Workloads under change-control regimes that don't permit
  third-party software installation

For all of these, the **device's own NetFlow / ERSPAN export** is
the right CSW visibility path. You'll typically use **NetFlow** if
the device can export it natively (most modern enterprise gear can
— Catalyst 9000, Nexus 9000, ASR / ISR, ASA / FTD, Meraki MX, F5,
NetScaler), and fall back to **ERSPAN** when only port-mirroring is
available.

**What you give up vs. an agent.**

- No process-level attribution — only flow-level data (5-tuple +
  counters, plus whatever metadata the source device adds).
- No software inventory or CVE lookup for that workload.
- No workload-side enforcement (the device's own ACLs / policies
  are still in play; CSW just ingests its flows).

**Deployment model.**

1. Deploy a **Secure Workload Ingest Appliance** in the same
   network zone as the source devices (the appliance receives
   NetFlow/ERSPAN traffic, which you don't want traversing the
   public internet or arbitrary firewalls).
2. Enable the relevant connector on the appliance from the CSW
   UI (*Manage → External Orchestrators / Connectors → NetFlow*
   or *ERSPAN* or one of the vendor-specific connectors).
3. Configure the source device to **export NetFlow / IPFIX** to
   the appliance's IP at the connector's port (or, for ERSPAN,
   configure a SPAN session that tunnels via GRE to the appliance).
4. Within minutes, flows appear against the source device in the
   CSW UI, attributed by the connector type.

For the exact source-device configuration (IOS / NX-OS NetFlow
exporter / monitor, ERSPAN session syntax, ASA NSEL config, F5
IPFIX template, Meraki dashboard NetFlow toggle), see the per-
connector subsections of the [Connectors chapter on
docs.cisco.com](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html).

> **Why this replaces the old "Hardware Sensor" framing.** Earlier
> CSW / Tetration generations shipped a dedicated hardware
> appliance with capture NICs that you wired into a SPAN / TAP
> port and that produced flow records from the raw packet stream.
> Modern CSW deployments instead lean on the **NetFlow / ERSPAN
> exports the network device already produces**, processed by a
> connector on a Secure Workload Ingest Appliance — same outcome
> (flow visibility for workloads that can't run an agent), much
> lower physical / cabling overhead, and on the same connector
> framework as AnyConnect, ISE, and the cloud connectors.

---

## 6. Cloud Sensor / Cloud Connector (agentless)

**What it does.** CSW *External Orchestrators / Connectors* poll
the cloud control plane (AWS, Azure, GCP) or the virtualisation
control plane (vCenter) for inventory metadata and flow log data
(VPC Flow Logs / NSG Flow Logs / VPC Flow Logs respectively). No
agent runs on the workload.

**What it provides:**

- Continuous inventory of cloud workloads with metadata (tags,
  region, security group, network interface)
- Flow-log-grade visibility (5-tuple + counters; no process
  attribution)
- Reconciliation against the host-agent inventory (CSW knows which
  cloud workloads have an agent and which don't)

**What it doesn't provide:**

- Process attribution
- Software inventory
- Vulnerability lookup
- Workload-side enforcement
- Sub-flow-log latency on flow data

**When to use.**
- Cloud accounts where the agent footprint is intentionally
  minimised (sandbox, DR, partner accounts).
- Workloads that aren't accessible to the agent install team but
  are still in scope for inventory.
- As a complementary signal alongside the host agent — connectors
  catch unmanaged shadow workloads that the host inventory misses.

**When NOT to use.**
- As a replacement for host agents on workloads you can deploy on.
  The host agent is meaningfully richer; use the connector to
  catch the gaps, not as the primary control.

Full coverage in the [`../agentless/`](../agentless/) section.

---

## Decision table

| Workload type | Recommended sensor | Reason |
|---|---|---|
| Linux server, supported OS, want enforcement | **Enforcement** | Deep Visibility + workload firewall enforcement |
| Linux server, supported OS, visibility only | **Deep Visibility** | Default for any host-class workload |
| Linux server, OS / kernel not on matrix | **Universal Visibility** | Broader compatibility, no kernel module |
| Windows server, supported OS, want enforcement | **Enforcement** | Deep Visibility + WFP-based enforcement |
| Windows server, supported OS, visibility only | **Deep Visibility** | Default for Windows server-class |
| Corporate laptop / desktop | **AnyConnect NVM** | Delivered via Cisco Secure Client |
| Network appliance (LB, FW, controller) | **NetFlow / ERSPAN ingestion** via the appropriate connector | Use the device's own NetFlow / IPFIX / NSEL export where available; fall back to ERSPAN when only port-mirroring is supported |
| Storage / SAN appliance | **ERSPAN** to the ERSPAN connector | Storage controllers rarely export NetFlow; mirror the storage VLAN and tunnel via GRE to the Ingest Appliance |
| OT system (PLC, RTU, HMI) | **NetFlow / ERSPAN** from the upstream switch (not from the OT device itself) | Never put a CSW agent on an OT device; pair with an OT-aware platform — Cisco Cyber Vision, Claroty, Nozomi, Dragos |
| Cloud workload, in active CSW scope | **Deep Visibility / Enforcement** (agent) | Agent gives process-level depth |
| Cloud account, broad inventory needed but agent footprint capped | **Cloud Connector** (agentless) | Inventory + flow-log tier without per-VM agent |
| Kubernetes / OpenShift node | **Deep Visibility** via DaemonSet | Standard K8s pattern |
| Kubernetes pod-level visibility | DaemonSet on the node provides flow telemetry to the cluster level | Container telemetry is captured at the node, not in each pod |

---

## See also

- [`00-official-references.md`](./00-official-references.md) — Cisco's authoritative pages, including the Connectors chapter
- [`01-prerequisites.md`](./01-prerequisites.md) — what to have before any install
- [`03-decision-matrix.md`](./03-decision-matrix.md) — once you've picked the sensor, pick the install method
- [`05-anyconnect-ise-alternatives.md`](./05-anyconnect-ise-alternatives.md) — endpoint-class agentless paths (AnyConnect NVM, ISE)
- [`../agentless/README.md`](../agentless/README.md) — cloud / vCenter connectors (the same "no agent" pattern, but for cloud and on-prem virtualisation)
- [`../operations/07-enforcement-rollout.md`](../operations/07-enforcement-rollout.md) — promoting Deep Visibility → Enforcement safely
