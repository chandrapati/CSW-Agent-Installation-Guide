# Agent Types — Pick the Right One

CSW ingests workload telemetry through several mechanisms. Some
require a host agent; others ingest from network devices, the
cloud control plane, or endpoint software you already deploy.

This page walks through what's actually documented in CSW 4.0
and ends with a one-page decision table.

> **Official sources.** All claims here cross-reference Cisco's
> two canonical chapters:
>
> - [Deploy Software Agents on Workloads (4.0 On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
>   — for the agent-based paths (Deep Visibility, Enforcement,
>   per-OS specifics including AIX / Solaris / Kubernetes).
> - [Configure and Manage Connectors for Secure Workload (4.0 On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html)
>   — for the agentless flow-ingest paths (NetFlow, ERSPAN,
>   AnyConnect, ISE, F5, NetScaler, Meraki, Secure Firewall, AWS,
>   Azure, GCP, vCenter).
>
> For exact OS / kernel / version coverage, the chapter directs
> you to the **Compatibility Matrix** at
> [`cisco.com/go/secure-workload/requirements/agents`](https://www.cisco.com/go/secure-workload/requirements/agents)
> or the public
> [Compatibility Matrix](https://www.cisco.com/c/m/en_us/products/security/secure-workload-compatibility-matrix.html),
> and to your cluster's *Manage → Workloads → Agents → Installer*
> screen, which is generated for your specific release.

> **Naming note.** Cisco's 4.0 Deploy Software Agents chapter
> describes only two host-agent *types*: **Deep Visibility** and
> **Enforcement**. Older Tetration-era documents distinguished a
> separate "Universal Visibility" SKU; that distinction is not
> retained as a separate type in the 4.0 chapter. Where this
> guide previously said "Universal Visibility" it now says
> "Deep Visibility on platforms that do not support enforcement"
> (e.g. AIX, Solaris). If you find UV terminology elsewhere in
> this repo, treat it as a callout for the older naming, not a
> separate product.

---

## At a glance

| Path | Telemetry | Enforcement | Where it runs | How it's installed |
|---|---|---|---|---|
| **Deep Visibility (Linux / Windows / AIX / Solaris / Kubernetes)** | Flow + process + software inventory + vulnerability lookup | No | On the workload | Agent Script Installer (preferred) or Agent Image Installer (RPM / DEB / MSI / TGZ) |
| **Enforcement (Linux / Windows / Kubernetes)** | Everything Deep Visibility produces | **Yes** — workload-side firewall (iptables / nftables / WFP) | On the workload | Same installers as Deep Visibility; enforcement is enabled by **Agent Config Profile**, not by a separate package |
| **AnyConnect NVM** | Endpoint flow telemetry from user devices | No | On user laptops / desktops via Cisco Secure Client | NVM module of Cisco Secure Client; ingest via **AnyConnect connector** on a Secure Workload Ingest Appliance |
| **ISE / pxGrid integration** | Endpoint identity / posture / context | No | On the ISE deployment | **ISE connector** on a Secure Workload Ingest Appliance, talking pxGrid |
| **NetFlow / IPFIX / ERSPAN / NSEL ingestion** | Flow records from the network device | No | The network device exports; the **connector** on an Ingest Appliance receives | NetFlow / ERSPAN / Cisco Secure Firewall / Meraki / F5 / NetScaler connectors |
| **Cloud Connector (AWS / Azure / GCP / vCenter)** | Inventory metadata + cloud flow logs | No | In CSW (or on an Ingest Appliance), via cloud APIs | *Manage → External Orchestrators / Connectors* |

The first two — **Deep Visibility** and **Enforcement** — cover
the overwhelming majority of customer fleets. The remaining
paths are for situations where a host agent is either
unsupported, not desired, or unavailable.

---

## 1. Deep Visibility — the default host agent

**What it does.** Captures every network flow, every process
spawn, every software-package change, and every kernel-level
event of interest, and forwards a structured stream to the
CSW cluster. Also performs vulnerability lookup against the
installed package list and returns CVE context per workload.

**What it doesn't do.** It does **not** apply firewall rules at
the host. The workload's existing firewall (iptables / nftables
/ Windows Filtering Platform) is unchanged when the agent is in
Deep Visibility mode. Use this for visibility, Automatic Policy
Discovery (ADM), and policy authoring. Promote to Enforcement
only when ready to enforce.

**OS support.** Per the *Deploy Software Agents* chapter, the
4.0 agent ships installers for:

- **Linux** — broad current-distribution coverage (RHEL /
  CentOS / Alma / Rocky, Ubuntu, Debian, Oracle Linux, SLES,
  Amazon Linux). Exact kernels per the Compatibility Matrix.
- **Windows** — Windows Server (with explicit notes about
  2008 R2 needing Npcap; modern releases use the in-box
  `ndiscap.sys`). See
  [`../windows/02-troubleshooting.md`](../windows/02-troubleshooting.md).
- **AIX** — Cisco's chapter has a dedicated *Install AIX
  Agents* section. Enforcement on AIX is not advertised in the
  same way as Linux / Windows; treat AIX as visibility-first
  unless the matrix for your release says otherwise.
- **Solaris** — Cisco's chapter has a dedicated *Install
  Solaris Agents* section (Solaris 10 and Solaris 11.4). Same
  caveat as AIX: confirm enforcement support on the matrix for
  your release.
- **Kubernetes / OpenShift** — DaemonSet pattern, deployed via
  the **Agent Script Installer** which generates a
  per-environment install script. See
  [`../kubernetes/`](../kubernetes/).

**Service / process names** (Cisco-documented; *Manage →
Workloads → Agents → Configure Security Exclusions* in the UI
displays these alongside the recommended AV / EDR exclusions):

- Linux service: `csw-agent` (systemd unit). Process names:
  `tet-sensor` (the agent), and on enforcement-enabled hosts
  `tet-enforcer`. (Some legacy cluster releases still ship the
  Tetration-era `tet-engine` controller; per Cisco the user-
  visible service is `csw-agent`.)
- Windows service: `CswAgent` (display name; service short
  name `cswagent`). Process names: `CswEngine.exe`,
  `TetEnfC.exe` (on enforcement-enabled hosts), and helpers
  per the Security Exclusions screen.

> Older Tetration-era docs and some on-disk paths refer to
> `tetd`, `tet-sensor`, `CswEngine.exe`, etc. The user-facing
> service in CSW 4.0 is `csw-agent` / `CswAgent` per the
> chapter; underlying processes still carry the `tet-` prefix.
> See [`00-official-references.md`](./00-official-references.md).

**When to use.**
- You want to see who is talking to whom and which processes
  are initiating it.
- You want continuous CVE inventory per workload with
  reachability context.
- You're in the build phase of a CSW deployment and policy is
  still being designed.

**When NOT to use.**
- The workload's OS or kernel is not on the matrix → use
  network-tier or agentless paths (sections 4–6).
- The workload type forbids third-party agents (network
  appliances, storage controllers, OT) → use **NetFlow /
  ERSPAN ingestion** or the appropriate cloud / vCenter
  connector instead.

---

## 2. Enforcement — Deep Visibility + workload firewall

**What it does.** Everything Deep Visibility does, **plus**
applies CSW-managed firewall rules at the workload kernel —
iptables / nftables on Linux, the Windows Filtering Platform on
Windows. The CSW cluster becomes the policy decision point; the
agent becomes the policy enforcement point.

**What it doesn't do.** Replace your network firewall. CSW
enforcement is the workload-tier control; you still need
perimeter and segment-level firewalls for everything outside
the agent's scope.

**OS support.** Per the *Deploy Software Agents* chapter, the
modern Linux and Windows agent ships with both visibility and
enforcement capability **in the same package** — there is no
separate "enforcement-only" installer. Whether the agent
actually enforces is controlled by the cluster-side **Agent
Config Profile**.

> **Same binary, different config.** Per Cisco: the agent
> install installs the enforcement capability; whether it
> engages depends on the agent config the cluster pushes down.
> So the install path for a future-enforcement host is
> identical to a visibility-only host — you do not reinstall
> when promoting to Enforcement.

**When to use.**
- After the workload has been on Deep Visibility long enough
  for ADM / policy authoring + at least one **Live Policy
  Analysis** cycle (typically 30 days for stability, longer
  for batch / monthly workloads).
- When the workload is in scope for a control that requires
  workload-level least-privilege (HIPAA, PCI, NIST AC-3, CSF
  PR.IR-01, etc.).

**When NOT to use.**
- Day-one of any deployment. Always start with Deep Visibility.
- Workloads where the change ticket can't get approved for a
  workload-side firewall change. Stay in Deep Visibility on
  those hosts and rely on network-tier enforcement.

**Operational note.** Per Cisco, Linux / Windows hosts run the
agent in privileged context: as **root on Linux, as SYSTEM on
Windows.** The Security Exclusions screen also calls out the
specific binaries / paths to exclude from AV/EDR. See
[`../operations/07-enforcement-rollout.md`](../operations/07-enforcement-rollout.md).

---

## 3. AnyConnect NVM — endpoint flow telemetry via Cisco Secure Client

**What it does.** Endpoint flow telemetry from user devices
(laptops / desktops). Delivered via **Cisco Secure Client**
(the product formerly known as AnyConnect) — the Network
Visibility Module sits alongside the VPN client and exports
flow records per the IPFIX-style NVM specification.

**Important — no CSW agent on the endpoint.** When NVM is in
use, you do **not** install a Deep Visibility agent on the
endpoint. CSW receives endpoint visibility through the
**AnyConnect connector** running on a Secure Workload Ingest
Appliance: the Secure Client / NVM endpoints stream IPFIX-NVM
to the connector, which forwards observations into the cluster.
See [`05-anyconnect-ise-alternatives.md`](./05-anyconnect-ise-alternatives.md).

**Why it's separate.** User-endpoint visibility has a different
operational model than server-class visibility:

- Endpoints are typically not always-on; the NVM module
  buffers and sends when connectivity is available.
- Endpoints typically don't enforce CSW-authored
  micro-segmentation policy; the policy decision point lives
  elsewhere (Duo / ZTNA / MDM stack).
- Per-process telemetry on a corporate laptop has different
  privacy considerations than on a server.

**When to use.**
- You want flow visibility from corporate laptops in addition
  to servers.
- You already deploy Cisco Secure Client to those laptops.

**When NOT to use.**
- You only care about server-class workloads.
- Cisco Secure Client isn't part of your endpoint strategy.

**Where to deploy from.** MDM (Intune, Workspace ONE, Jamf for
macOS) is the standard delivery channel. NVM is a sub-feature
of Secure Client — enabled at install time via the Secure
Client profile.

---

## 4. ISE / pxGrid — endpoint identity and posture context

**What it does.** Pulls endpoint identity, posture, and
session context from a Cisco ISE deployment via pxGrid. CSW
uses this to label and correlate endpoint flows that arrive
from other sources (typically NVM or NetFlow from the access
layer).

**No agent on the endpoint.** The ISE connector talks pxGrid;
endpoints don't get a CSW agent for this path.

**When to use.** You already have ISE; you want CSW to see
endpoints the same way the rest of your security stack does
(by user, by posture, by session).

For details, see Cisco's [ISE Connector](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html#concept_lpd_v3w_l1c)
section in the Connectors chapter, and
[`05-anyconnect-ise-alternatives.md`](./05-anyconnect-ise-alternatives.md).

---

## 5. NetFlow / IPFIX / ERSPAN / NSEL ingestion — agentless flow for non-agent workloads

**What it does.** For workloads that can't run a CSW host agent,
CSW ingests **flow records exported by the network device**
rather than instrumenting the workload itself. The network
device — Catalyst / Nexus switch, ASR / ISR router, ASA / FTD
firewall, Meraki MX, F5 BIG-IP, Citrix NetScaler — exports flows
in NetFlow v9 / IPFIX / ERSPAN / NSEL format to a **Secure
Workload Ingest Appliance** in your DC. The matching connector
running on that appliance receives the flow records, processes
them, and reports flow observations to the CSW cluster.

> **Official source.** [Configure and Manage Connectors for
> Secure Workload (4.0 On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html).
> The same chapter exists in the SaaS user guide. The connector
> configuration UI in CSW lives at *Manage → External
> Orchestrators / Connectors*.

**Connectors available for flow ingestion (CSW 4.0).** All run
as Docker containers on a Secure Workload Ingest Appliance:

| Connector | Source format | Use it for |
|---|---|---|
| **NetFlow** | NetFlow v9 / IPFIX | Generic flow ingest from any device that can export NetFlow / IPFIX |
| **ERSPAN** | Encapsulated Remote SPAN (GRE-tunnelled mirror) | When the device can mirror traffic but doesn't export NetFlow; close to the old "tap a SPAN port" model |
| **Cisco Secure Firewall** (formerly ASA Connector) | NetFlow Secure Event Logging (NSEL) from ASA / FTD | Cisco Secure Firewall estate |
| **Meraki** | NetFlow v9 from Meraki MX | Meraki SD-WAN / branch firewalls |
| **F5** | F5 BIG-IP IPFIX | Application-tier visibility behind an F5 |
| **NetScaler** | Citrix NetScaler AppFlow | Citrix-fronted apps |

**Why this matters.** Some workload classes forbid CSW host
agents:

- Network appliances (load balancers, firewalls, controllers,
  WAN-optimisers)
- Storage / SAN / NAS controllers
- OT systems (PLCs, RTUs, IEDs, HMIs) — never deploy a server
  agent on these; pair this approach with OT-aware monitoring
  (Cisco Cyber Vision, Claroty, Nozomi, Dragos)
- Embedded medical / industrial devices
- Workloads under change-control regimes that don't permit
  third-party software installation

For all of these, the **device's own NetFlow / ERSPAN export**
is the right CSW visibility path. You'll typically use **NetFlow**
if the device can export it natively (most modern enterprise
gear can — Catalyst 9000, Nexus 9000, ASR / ISR, ASA / FTD,
Meraki MX, F5, NetScaler), and fall back to **ERSPAN** when only
port-mirroring is available.

**What you give up vs. an agent.**

- No process-level attribution — only flow-level data (5-tuple
  + counters, plus whatever metadata the source device adds).
- No software inventory or CVE lookup for that workload.
- No workload-side enforcement (the device's own ACLs / policies
  are still in play; CSW just ingests its flows).

**Deployment model.**

1. Deploy a **Secure Workload Ingest Appliance** in the same
   network zone as the source devices (the appliance receives
   NetFlow / ERSPAN traffic, which you don't want traversing
   the public internet or arbitrary firewalls).
2. Enable the relevant connector on the appliance from the CSW
   UI (*Manage → External Orchestrators / Connectors → NetFlow*
   or *ERSPAN* or one of the vendor-specific connectors).
3. Configure the source device to **export NetFlow / IPFIX**
   to the appliance's IP at the connector's port (or, for
   ERSPAN, configure a SPAN session that tunnels via GRE to
   the appliance).
4. Within minutes, flows appear against the source device in
   the CSW UI, attributed by the connector type.

For the exact source-device configuration (IOS / NX-OS NetFlow
exporter / monitor, ERSPAN session syntax, ASA NSEL config, F5
IPFIX template, Meraki dashboard NetFlow toggle), see the
per-connector subsections of the [Connectors chapter on
docs.cisco.com](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html).

> **Why this replaces the old "Hardware Sensor" framing.**
> Earlier Tetration generations shipped a dedicated hardware
> appliance with capture NICs that you wired into a SPAN / TAP
> port and that produced flow records from the raw packet
> stream. Modern CSW deployments instead lean on the **NetFlow
> / ERSPAN exports the network device already produces**,
> processed by a connector on a Secure Workload Ingest
> Appliance — same outcome (flow visibility for workloads that
> can't run an agent), much lower physical / cabling overhead,
> and on the same connector framework as AnyConnect, ISE, and
> the cloud connectors.

---

## 6. Cloud Connector — agentless cloud / virtualisation inventory + flow logs

**What it does.** CSW *External Orchestrators / Connectors* poll
the cloud control plane (AWS, Azure, GCP) or the virtualisation
control plane (vCenter) for inventory metadata and flow log
data (VPC Flow Logs / NSG Flow Logs / VPC Flow Logs
respectively). No agent runs on the workload.

**What it provides:**

- Continuous inventory of cloud workloads with metadata (tags,
  region, security group, network interface)
- Flow-log-grade visibility (5-tuple + counters; no process
  attribution)
- Reconciliation against the host-agent inventory (CSW knows
  which cloud workloads have an agent and which don't)

**What it doesn't provide:**

- Process attribution
- Software inventory
- Vulnerability lookup
- Workload-side enforcement
- Sub-flow-log latency on flow data

**When to use.**
- Cloud accounts where the agent footprint is intentionally
  minimised (sandbox, DR, partner accounts).
- Workloads that aren't accessible to the agent install team
  but are still in scope for inventory.
- As a complementary signal alongside the host agent —
  connectors catch unmanaged shadow workloads that the host
  inventory misses.

**When NOT to use.**
- As a replacement for host agents on workloads you can deploy
  on. The host agent is meaningfully richer; use the connector
  to catch the gaps, not as the primary control.

Full coverage in the [`../agentless/`](../agentless/) section.

---

## Decision table

| Workload type | Recommended path | Reason |
|---|---|---|
| Linux server, supported OS, want enforcement | **Enforcement** (Deep Visibility agent + Enforcement Agent Config Profile) | Same binary as Deep Visibility; Enforcement engaged via cluster config |
| Linux server, supported OS, visibility only | **Deep Visibility** | Default for any host-class workload |
| Linux server, OS / kernel not on matrix | **Agentless** — NetFlow from upstream switch, or Cloud Connector | No agent path; rely on network or cloud telemetry |
| Windows Server, supported version, want enforcement | **Enforcement** | Same as Linux; one binary, two modes |
| Windows Server, supported version, visibility only | **Deep Visibility** | Default for Windows server-class |
| Windows Server 2008 R2 (legacy) | Deep Visibility, but verify Npcap requirement on matrix | Older agents and 2008 R2 use **Npcap**; modern Windows uses `ndiscap.sys` |
| AIX server | **Deep Visibility (AIX agent)** | Cisco's Install AIX Agents section; verify enforcement availability for your release |
| Solaris 10 / 11.4 server | **Deep Visibility (Solaris agent)** | Cisco's Install Solaris Agents section |
| Corporate laptop / desktop | **AnyConnect NVM** + AnyConnect connector | Endpoint visibility via Cisco Secure Client; no host agent on the laptop |
| ISE-managed endpoints (you want identity / posture context) | **ISE connector via pxGrid** | Endpoint context without an agent on the endpoint |
| Network appliance (LB, FW, controller) | **NetFlow / ERSPAN / NSEL** via the appropriate connector | Use the device's own export where available |
| Storage / SAN appliance | **ERSPAN** to the ERSPAN connector | Storage controllers rarely export NetFlow; mirror the storage VLAN |
| OT system (PLC, RTU, HMI) | **NetFlow / ERSPAN** from the upstream switch (not from the OT device itself) | Never put a CSW agent on an OT device |
| Cloud workload, in active CSW scope | **Deep Visibility / Enforcement** (agent) | Agent gives process-level depth |
| Cloud account, broad inventory needed but agent footprint capped | **Cloud Connector** (agentless) | Inventory + flow-log tier without per-VM agent |
| Kubernetes / OpenShift node | **Deep Visibility / Enforcement** via DaemonSet (Agent Script Installer) | Standard K8s pattern in Cisco's chapter |
| Kubernetes pod-level visibility | DaemonSet on the node provides flow telemetry to the cluster level | Container telemetry is captured at the node, not in each pod |

---

## See also

- [`00-official-references.md`](./00-official-references.md) — Cisco's authoritative pages, including the Connectors chapter
- [`01-prerequisites.md`](./01-prerequisites.md) — what to have before any install
- [`03-decision-matrix.md`](./03-decision-matrix.md) — once you've picked the agent type, pick the install method
- [`05-anyconnect-ise-alternatives.md`](./05-anyconnect-ise-alternatives.md) — endpoint-class agentless paths (AnyConnect NVM, ISE)
- [`../agentless/README.md`](../agentless/README.md) — cloud / vCenter connectors (the same "no agent" pattern, but for cloud and on-prem virtualisation)
- [`../operations/07-enforcement-rollout.md`](../operations/07-enforcement-rollout.md) — promoting Deep Visibility → Enforcement safely
