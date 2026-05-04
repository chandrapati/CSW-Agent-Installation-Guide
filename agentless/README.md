# Agentless — Cloud Connectors

When the host agent isn't the right answer, CSW's **Cloud
Connectors** (also called *External Orchestrators* in some
releases) ingest inventory and flow telemetry from cloud and
virtualisation control planes via API. No software runs on the
workload.

> **Official source.** All CSW connectors — cloud, vCenter,
> NetFlow / IPFIX, ERSPAN, AnyConnect, ISE, F5, NetScaler,
> Meraki, Secure Firewall — are documented in a single chapter
> of the User Guide:
> [Configure and Manage Connectors for Secure Workload (4.0
> On-Prem)](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/configure-and-manage-connectors-for-secure-workload.html).
> The same chapter exists in the SaaS user guide. The
> per-connector subsections include source-device
> configuration (e.g., NetFlow exporter syntax, ERSPAN session
> setup, AWS / Azure / GCP IAM scope) — refer to it in
> conjunction with the runbooks here.

> Connectors are **complementary** to the host agent, not a
> replacement. The agent has process attribution, software
> inventory, and CVE lookup that the connector cannot match. Use
> connectors to fill the gaps where agents don't fit.

---

## When to use a Cloud Connector

Best fits:

- **Cloud accounts where you can't deploy agents on every VM.**
  DR / sandbox accounts, partner-shared accounts, accounts under
  business-unit ownership where the central security team
  doesn't operate the workloads.
- **Workload-types where agents won't run.** AWS Fargate, GKE
  Autopilot, AWS Lambda, AKS Container Apps — none of these
  expose the host kernel namespace the agent needs.
- **Inventory reconciliation across the whole VPC / VNet /
  Project.** The connector enumerates the cloud-side reality;
  the host-agent inventory enumerates the agent-side reality.
  Diffing the two surfaces shadow workloads that have no agent
  installed (and shouldn't).
- **Flow-log–tier visibility for traffic you can't see otherwise.**
  Workloads that only talk to PaaS services (RDS, ALB, KMS) — the
  agent on a workload sees its own flows, but the PaaS endpoint
  is opaque to the agent. Cloud-provider flow logs surface this
  via the connector.

Not a fit:

- **As a replacement for the host agent on workloads you do
  control.** The agent is meaningfully richer.
- **For real-time policy enforcement.** Connectors operate on
  cloud-provider APIs and flow-log batching; the latency is
  minutes, not seconds. Agent-driven enforcement is the answer.

---

## Connectors in this folder

| # | Connector | Doc |
|---|---|---|
| 01 | AWS Cloud Connector | [01-aws-cloud-connector.md](./01-aws-cloud-connector.md) |
| 02 | Azure Cloud Connector | [02-azure-cloud-connector.md](./02-azure-cloud-connector.md) |
| 03 | GCP Cloud Connector | [03-gcp-cloud-connector.md](./03-gcp-cloud-connector.md) |
| 04 | vCenter Connector | [04-vcenter-connector.md](./04-vcenter-connector.md) |
| 05 | Comparison: Agent vs. Connector | [05-comparison-matrix.md](./05-comparison-matrix.md) |

---

## What every connector provides

Common across AWS / Azure / GCP / vCenter:

- **Continuous inventory** — every VM (or VNet / VPC object) the
  connector's identity can `Describe` or `Get` is enumerated and
  refreshed on a configurable cadence.
- **Metadata enrichment** — tags, labels, security groups / NSGs,
  network interface details, region, AZ.
- **Flow-log ingestion** (where supported) — VPC Flow Logs (AWS),
  NSG Flow Logs (Azure), VPC Flow Logs (GCP). Flow records with
  5-tuple, byte/packet counts, and Allow/Reject markers.
- **Reconciliation against host-agent inventory** — CSW knows
  which inventory items are also instrumented with an agent and
  which aren't.

What no connector provides:

- Process attribution per flow
- Software inventory per workload
- Vulnerability (CVE) lookup per workload
- Sub-flow-log latency on flow data
- Workload-side enforcement

---

## Identity and least privilege

Each connector authenticates to the cloud with a dedicated
identity:

| Cloud | Identity model | Recommended scoping |
|---|---|---|
| AWS | Cross-account IAM role assumed by CSW | One role per AWS account; trust policy locked to the CSW connector's principal; permission policy limited to `*:Describe*` / `*:List*` and flow-log read |
| Azure | Service principal or system-assigned identity for the connector workload | One SP per subscription; RBAC scope = subscription; role = `Reader` plus a custom role granting read on NSG flow log destinations |
| GCP | Service account in a customer-owned project; impersonated by the connector | One SA per organisation/project; IAM = `roles/viewer` plus `roles/logging.viewer` on flow-log destinations |
| vCenter | Read-only vSphere user | One user per vCenter; role = read-only inventory + tag access |

Detail in each per-connector doc.

---

## Operating model

Connectors run on the CSW side (in the cluster's connector
infrastructure) and pull data on a schedule. From your side:

1. Create the IAM artefacts (role / SP / SA / vSphere user)
2. Configure the connector in the CSW UI (*Manage → External
   Orchestrators* or release-equivalent path)
3. Validate connectivity and first inventory sync (typically
   within an hour)
4. Enable flow-log collection if you want flow telemetry
5. Schedule periodic reconciliation reviews (quarterly is a
   reasonable starting cadence)

---

## See also

- [`05-comparison-matrix.md`](./05-comparison-matrix.md) — agent vs. connector trade-offs in detail
- [`../docs/02-sensor-types.md`](../docs/02-sensor-types.md) — broader sensor-type discussion
- [`../cloud/`](../cloud/) — for the *agent* path on cloud VMs
