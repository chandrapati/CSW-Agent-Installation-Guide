# Agentless — Agent vs. Connector Comparison

The agent and the cloud connector solve different problems.
This doc lays out the trade-off in one place so teams can plan
the right blend.

---

## High-level summary

> **The agent gives you depth. The connector gives you breadth.**
> A mature CSW deployment usually combines both: agents on
> everything you can, connectors on everything you can't.

---

## Capability matrix

| Capability | Host agent | Cloud connector | Notes |
|---|---|---|---|
| Per-flow source/dest | yes | yes (from flow logs) | Connector latency is minutes; agent is near-real-time |
| Process attribution per flow | **yes** | no | Only the agent ties a flow to a process / container |
| Software inventory per workload | **yes** | partial (cloud-side metadata only) | Connector knows the VM type and image; agent knows installed packages |
| Vulnerability (CVE) lookup | **yes** | no | Agent reports installed packages → CSW correlates to CVE feed |
| Workload-side enforcement | **yes** | no | Connectors are read-only; enforcement requires the agent |
| Inventory of *every* cloud resource | partial | **yes** | Connector enumerates everything the cloud identity can `Describe` — agents only enumerate where they're installed |
| Coverage of *agentless* workload types | no | **yes** | Fargate / Autopilot / Lambda / managed PaaS — agent can't run, connector still ingests |
| First-party flow data on PaaS endpoints (RDS, ALB, KMS) | partial | **yes** | Cloud-provider flow logs see PaaS endpoints the agent can't |
| Real-time inventory drift detection | partial | **yes** | Connector's pull cadence catches new resources within minutes |
| Reconciliation (what's in the cloud vs. what's instrumented) | n/a | **yes** | Connector + agent compared = "shadow workload" report |
| Identity / RBAC scope to manage | per-host (CSW activation key) | per-cloud-account (cross-account role) | |
| Maintenance overhead | higher (per-host upgrades) | lower (set-and-forget once configured) | |
| Cost driver | per-workload license | per-flow-log volume + connector platform | |

---

## When the agent wins

- **Anywhere you do segmentation work.** Without process
  attribution and per-host policy, segmentation policy is at
  best guesswork.
- **Anywhere you do CVE / vulnerability response.** Cloud
  metadata can't tell you that a workload has an outdated
  OpenSSL package; the agent can.
- **Any host the security team owns the operations for.** If
  you can run the agent, you should — connectors are not a
  reason to skip the agent.
- **Real-time response.** Detection that has to act in seconds
  needs the agent.

---

## When the connector wins

- **Workloads you don't operate.** Partner-shared accounts,
  business-unit–owned subscriptions, DR / sandbox enclaves
  where central security has read-only oversight.
- **Workload types where the agent can't run.** Fargate, GKE
  Autopilot, Lambda, managed PaaS — the agent has nowhere to
  install. Connector + cloud-provider flow logs is the only
  visibility path.
- **Inventory reconciliation.** The connector enumerates the
  cloud-side reality; the agent enumerates the
  agent-installed reality. Diffing the two produces the
  "shadow workload" list.
- **Audit evidence on cloud-side configuration.** Connector
  metadata becomes evidence for cloud-config audits ("does
  every public-subnet VM have an attached IAM role with no
  admin permissions?")

---

## Common combinations in production

### Pattern 1 — Cloud-first segmentation programme

- Agent on every EC2 / Azure VM / GCE instance the team owns
  (Golden AMI / Compute Gallery Image / GCE custom image)
- Cloud connector on every cloud account (read-only inventory
  + flow logs)
- Reconciliation report run quarterly: list any workload in
  the connector inventory that isn't in the agent inventory →
  triage as either "needs agent" or "not in scope"

### Pattern 2 — Brownfield discovery

- Cloud connectors first, no agents yet
- Use the connector inventory to plan agent deployment
  prioritisation (most-trafficked VPCs first)
- Agent rollout follows, wave by wave (see
  [`../docs/04-rollout-strategy.md`](../docs/04-rollout-strategy.md))
- Connectors stay deployed for ongoing reconciliation

### Pattern 3 — Mixed control plane (some agent, some connector by design)

- Agent on production tiers
- Connector-only on workloads the security team explicitly
  doesn't operate (DR replicas, vendor-managed clusters,
  research sandboxes)
- The connector provides oversight ("show me everything the
  vendor is running"); the agent provides depth on the rest

### Pattern 4 — Kubernetes mixed mode

- DaemonSet sensor on Standard EKS / AKS / GKE clusters
- Cloud connector on the same cloud accounts
- Connector covers Fargate / Autopilot / Lambda / managed
  PaaS, plus reconciliation against the K8s sensor's
  per-pod inventory

---

## Frequently asked

### "Can I just use the connector and skip the agent?"

You can — but you'll lose process attribution, software
inventory, CVE lookup, and any path to enforcement. Some teams
start there to gather inventory data, then add agents in a
prioritised rollout.

### "Can I just use the agent and skip the connector?"

Yes, where every workload has an agent. The downside is that
shadow workloads — VMs nobody installed the agent on — won't
appear anywhere in CSW. The connector is the safety net.

### "Do connectors and agents conflict?"

No. The agent reports up to CSW directly; the connector pulls
inventory from the cloud control plane. CSW reconciles them
and de-duplicates.

### "Connector latency vs. agent latency?"

Agent: seconds (telemetry batched and shipped continuously).
Connector inventory: minutes (configurable pull cadence).
Connector flow logs: 5–15 minutes (cloud-provider batching).
For real-time work, the agent is the only answer.

---

## See also

- [`README.md`](./README.md) — agentless overview
- [`../docs/02-sensor-types.md`](../docs/02-sensor-types.md) — sensor-type comparison (broader)
- [`../docs/03-decision-matrix.md`](../docs/03-decision-matrix.md) — installation-method decision matrix
- [`../cloud/`](../cloud/) — agent path for cloud VMs
- [`../kubernetes/`](../kubernetes/) — agent path for Kubernetes
