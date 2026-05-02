# Sensor Types — Pick the Right One

CSW ships several sensor flavours. Each fits a different workload
profile. This doc walks through all six and ends with a one-page
decision table.

---

## At a glance

| Sensor type | Telemetry | Enforcement | Where it runs | Sensor binary / install |
|---|---|---|---|---|
| **Deep Visibility** | Flow + process + software inventory + vulnerability lookup | No (visibility only) | Linux, Windows host | `tet-sensor` package; `tetd` service |
| **Enforcement** | Everything Deep Visibility produces | **Yes** — workload-side firewall | Linux, Windows host | `tet-sensor-enforcer` package (or feature flag depending on release); `tetd` + `tet-enforcer` services |
| **Universal Visibility (UV)** | Flow + lighter process telemetry | No | Broader OS / kernel / arch coverage | `tet-sensor` (UV variant); user-space only |
| **AnyConnect NVM** | Endpoint flow telemetry from user devices | No (CSW-side; endpoint may be controlled by Cisco Secure Client) | macOS, Windows, Linux laptops via Cisco Secure Client | NVM module of Cisco Secure Client |
| **Hardware Sensor** | Flow ingest from a SPAN port (passive) | No | Network appliance / standalone server with capture NIC | CSW Hardware Sensor appliance |
| **Cloud Sensor / Cloud Connector** | Inventory + flow logs via cloud APIs | No | Runs *in CSW*, polling AWS / Azure / GCP / vCenter; **no agent on the workload** | CSW *External Orchestrators / Connectors* configuration |

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
- The workload type forbids third-party agents → use a Hardware
  Sensor or Cloud Connector instead.

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

**Operational note.** Enforcement is configured as an *agent
profile* setting in CSW *Manage → Agent Configuration*. The agent
binary is the same — what changes is the cluster-side instruction
to engage the enforcer module. See
[`../operations/07-enforcement-mode-rollout.md`](../operations/07-enforcement-mode-rollout.md).

---

## 3. Universal Visibility (UV) — broader OS coverage

**What it does.** Lighter-weight flow telemetry and process
inventory, in user space only. No kernel module, no enforcement.

**Why it exists.** The Deep agent's kernel module is tied to
specific OS / kernel combinations. UV widens the net to:

- Older Linux (RHEL 5/6 era) where the Deep module isn't built
- ARM64 Linux
- Some specialised distros / niche kernels
- Solaris / AIX tiers (per the Compatibility Matrix at your release)

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

## 5. Hardware Sensor

**What it does.** A dedicated CSW Hardware Sensor appliance (or
qualified server with a capture NIC) ingests traffic from a network
SPAN / TAP port, generates flow records from the packet stream, and
forwards them to the CSW cluster. **Passive** — does not interact
with the workload.

**Why it exists.** Some workload classes forbid agents:

- Network appliances (load balancers, firewalls, controllers)
- Storage appliances (SAN, NAS controllers)
- OT systems (PLCs, RTUs, IEDs, HMIs) — never put a server agent
  on those
- Embedded medical / industrial devices
- Workloads under change-control regimes that don't permit
  third-party software installation

**What you give up vs. an agent.**

- No process-level attribution (only flow-level data).
- No software inventory or CVE lookup for that workload.
- No workload-side enforcement.

**Deployment model.** Mirror the relevant traffic to a SPAN
destination port, connect the Hardware Sensor capture NIC, register
the appliance with the cluster.

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
| Network appliance (LB, FW, controller) | **Hardware Sensor** (SPAN) | No agent permitted on appliance |
| Storage / SAN appliance | **Hardware Sensor** (SPAN) | No agent permitted on appliance |
| OT system (PLC, RTU, HMI) | **Hardware Sensor** (SPAN) | No agent permitted; OT-aware monitoring also recommended (Cisco Cyber Vision, Claroty, Nozomi, Dragos) |
| Cloud workload, in active CSW scope | **Deep Visibility / Enforcement** (agent) | Agent gives process-level depth |
| Cloud account, broad inventory needed but agent footprint capped | **Cloud Connector** (agentless) | Inventory + flow-log tier without per-VM agent |
| Kubernetes / OpenShift node | **Deep Visibility** via DaemonSet | Standard K8s pattern |
| Kubernetes pod-level visibility | DaemonSet on the node provides flow telemetry to the cluster level | Container telemetry is captured at the node, not in each pod |

---

## See also

- [`01-prerequisites.md`](./01-prerequisites.md) — what to have before any install
- [`03-decision-matrix.md`](./03-decision-matrix.md) — once you've picked the sensor, pick the install method
- [`../agentless/README.md`](../agentless/README.md) — when (and when not) to use the Cloud Connector
- [`../operations/07-enforcement-mode-rollout.md`](../operations/07-enforcement-mode-rollout.md) — promoting Deep Visibility → Enforcement safely
