# Kubernetes — Installation Methods

Patterns for running the CSW agent on Kubernetes (and OpenShift)
nodes. The agent runs as a **DaemonSet** — one privileged agent
pod per node — capturing host-level network flows for both the
node and the workload pods scheduled on it.

> **Authoritative source.** The Cisco-documented installation
> path for Kubernetes / OpenShift is the **Agent Script
> Installer** under *Manage → Workloads → Agents → Installer*.
> Per Cisco's
> [Install Kubernetes or OpenShift Agents for Deep Visibility and Enforcement](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
> section, this script generates the namespace (Cisco's
> documented namespace is **`tetration`**), RBAC, ConfigMap /
> Secret, and DaemonSet for the cluster you point it at; nodes
> then pull the agent image from the cluster at pod startup.

> **Helm chart vs. raw manifest patterns in this folder are
> community patterns**, not Cisco-published in the 4.0 chapter.
> They're useful for shops that want to manage the install
> through their existing Helm or GitOps pipelines, but: (a) the
> Cisco-supported install path remains the Agent Script
> Installer, and (b) the chart / manifest contents below are
> *modelled on* what the Agent Script Installer produces — your
> mileage in production depends on keeping them aligned with
> what the script generates for the agent version you run.

> **Architectural point.** CSW does not run a sidecar in every
> workload pod. Telemetry is captured at the **node** level by
> the sensor pod and attributed back to pods, services, and
> namespaces using the cluster's metadata. CSW sees pod-to-pod
> and pod-to-external flows; intra-pod traffic (between
> containers in the same pod) is not the unit of capture.

> **CSW 4.0 — important architectural detail.** The Kubernetes /
> OpenShift installer script does **not** contain the agent
> software itself. The script provisions namespace, RBAC, the
> DaemonSet, and configuration — and **each cluster node pulls
> the agent Docker image from the Secure Workload cluster** at
> pod startup time. This means cluster nodes need image-pull
> connectivity to the CSW cluster (or to your internal registry
> mirror — see [`01-daemonset-helm.md`](./01-daemonset-helm.md)).
> See [`../docs/00-official-references.md`](../docs/00-official-references.md)
> for the User Guide reference.

> **Service mesh + CNI support (CSW 4.0).**
> - **Istio Service Mesh:** CSW provides comprehensive visibility
>   and enforcement for applications running within Kubernetes /
>   OpenShift clusters that have Istio enabled.
> - **Calico:** CSW 4.0 supports **Calico 3.13** with one of the
>   following Felix configurations:
>   - `ChainInsertMode: Append, IptablesRefreshInterval: 0`, or
>   - `ChainInsertMode: Insert, IptablesFilterAllowAction: Return,
>     IptablesMangleAllowAction: Return, IptablesRefreshInterval: 0`
>   If your Calico version or Felix config differs, validate
>   with Cisco TAC before relying on CSW enforcement on that
>   cluster.

---

## Methods in this folder

| # | Method | Best for | Cisco-documented? | Doc |
|---|---|---|---|---|
| — | **Agent Script Installer** *(Cisco's documented method)* | Default for any K8s / OpenShift cluster | **Yes** — see Cisco's [Install Kubernetes or OpenShift Agents](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html) section | (in your cluster's UI: *Manage → Workloads → Agents → Installer*) |
| 01 | DaemonSet via Helm chart *(community pattern)* | Shops standardised on Helm / GitOps | No | [01-daemonset-helm.md](./01-daemonset-helm.md) |
| 02 | DaemonSet via raw manifest *(community pattern)* | Air-gapped clusters, no-Helm shops | No | [02-daemonset-yaml.md](./02-daemonset-yaml.md) |
| 03 | EKS / AKS / GKE notes | Cloud K8s services | Partial — these are practitioner notes on top of the Cisco-documented install | [03-eks-aks-gke.md](./03-eks-aks-gke.md) |
| 04 | OpenShift — SCC adjustments | OpenShift / OKD clusters | Cisco's chapter has an OpenShift sub-section; details here go beyond | [04-openshift.md](./04-openshift.md) |
| 05 | Verification | Confirming the install actually worked | Practitioner guide | [05-verification.md](./05-verification.md) |

---

## Prerequisites

The general items in
[`../docs/01-prerequisites.md`](../docs/01-prerequisites.md) all
apply, with these additions:

- **Privileged pod execution.** The agent pod needs
  `securityContext.privileged: true`, `hostNetwork: true`,
  `hostPID: true`, and `volumeMounts` to host paths
  (`/proc`, `/sys`, `/var/log`).
- **Pod Security Admission (PSA).** Default `restricted` profile
  blocks privileged pods. Cisco documents that Secure Workload
  entities are created in the **`tetration`** namespace. If your
  Kubernetes version enforces PSA, allow privileged pods for that
  namespace according to your cluster policy.
- **OpenShift / SCC.** OpenShift adds Security Context
  Constraints on top of PSA. The agent namespace needs the
  `privileged` SCC bound to the agent's ServiceAccount. See
  [04-openshift.md](./04-openshift.md).
- **Image registry access.** The agent image must be reachable
  from cluster nodes. By default the cluster nodes pull the
  image from the **CSW cluster itself** (Cisco's documented
  flow); for air-gapped or constrained networks, mirror to an
  internal registry.

---

## Sensor type for Kubernetes

- **Deep Visibility** is the default for K8s nodes. Cisco offers
  Enforcement on K8s nodes in some releases — validate against
  your release. In Enforcement mode, policy applies at the host
  firewall managed by the sensor; this affects all pod traffic
  that traverses the node's kernel.
- The sensor picks up Kubernetes metadata (pod name, namespace,
  labels, deployment) so the cluster sees per-pod attribution
  rather than just node-level flows.

---

## Conventions used throughout

| Item | Cisco-documented (Agent Script Installer) | Community-pattern files (01, 02 in this folder) |
|---|---|---|
| Namespace | **`tetration`** | Use `tetration` unless your generated installer output differs |
| ServiceAccount | (per the script's output) | Copy from the generated installer output |
| ClusterRole | (per the script's output) | Copy from the generated installer output |
| Image source | **CSW cluster itself** — nodes pull from `CFG-SERVER:443` | Mirrored to internal registry; supplied via `image.repository` override |
| DaemonSet name | (per the script's output) | Copy from the generated installer output |
| Configuration source | (per the script's output) | Do not invent Secret keys; copy from the generated installer output |

> **In production**, the simplest correct path is: run the
> Agent Script Installer once per cluster, capture what it
> creates (`kubectl get all -n tetration -o yaml`), and use
> *that* as your GitOps source of truth — not the community
> snippets in this folder.

---

## Common gotchas (cluster-wide)

- **DaemonSet pod stuck in `Pending`** — usually missing
  privileged PSA label or PSP / SCC rejection. Check namespace
  label and pod events.
- **Sensor registers but reports zero flows** — verify
  `hostNetwork: true` and the host-path mounts; without them the
  sensor sees only its own pod network namespace.
- **Image pull fails** — air-gapped clusters need the sensor
  image mirrored to an internal registry; override
  `image.repository`.
- **Worker nodes tainted (e.g., control-plane)** — add
  tolerations in the DaemonSet for the taints you want covered.

Full troubleshooting in
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## See also

- [`../docs/00-official-references.md`](../docs/00-official-references.md) — CSW 4.0 official-doc cross-reference (Istio, Calico, K8s image-pull architecture)
- [`../docs/`](../docs/) — prerequisites, sensor types, decision matrix, rollout strategy
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)
