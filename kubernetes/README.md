# Kubernetes — Installation Methods

Patterns for running the CSW sensor on Kubernetes (and OpenShift)
nodes. The sensor runs as a **DaemonSet** — one privileged sensor
pod per node — capturing host-level network flows for both the
node and the workload pods scheduled on it.

> **Architectural point.** CSW does not run a sidecar in every
> workload pod. Telemetry is captured at the **node** level by
> the sensor pod and attributed back to pods, services, and
> namespaces using the cluster's metadata. CSW sees pod-to-pod
> and pod-to-external flows; intra-pod traffic (between
> containers in the same pod) is not the unit of capture.

---

## Methods in this folder

| # | Method | Best for | Doc |
|---|---|---|---|
| 01 | DaemonSet via Helm chart | Standard pattern; any K8s distro | [01-daemonset-helm.md](./01-daemonset-helm.md) |
| 02 | DaemonSet via raw manifest | Air-gapped clusters, no-Helm shops | [02-daemonset-yaml.md](./02-daemonset-yaml.md) |
| 03 | EKS / AKS / GKE notes | Cloud K8s services | [03-eks-aks-gke.md](./03-eks-aks-gke.md) |
| 04 | OpenShift — SCC adjustments | OpenShift / OKD clusters | [04-openshift.md](./04-openshift.md) |
| 05 | Verification | Confirming the install actually worked | [05-verification.md](./05-verification.md) |

---

## Prerequisites

The general items in
[`../docs/01-prerequisites.md`](../docs/01-prerequisites.md) all
apply, with these additions:

- **Privileged pod execution.** The sensor pod needs
  `securityContext.privileged: true`, `hostNetwork: true`,
  `hostPID: true`, and `volumeMounts` to host paths
  (`/proc`, `/sys`, `/var/log`).
- **Pod Security Admission (PSA).** Default `restricted` profile
  blocks privileged pods. Plan a dedicated namespace
  (conventionally `csw-sensor`) labelled
  `pod-security.kubernetes.io/enforce: privileged`.
- **OpenShift / SCC.** OpenShift adds Security Context Constraints
  on top of PSA. The sensor namespace needs the `privileged`
  SCC bound to the sensor's ServiceAccount. See
  [04-openshift.md](./04-openshift.md).
- **Image registry access.** The sensor image must be reachable
  from cluster nodes. Mirror to your internal registry for
  production and air-gapped clusters.

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

| Item | Conventional value |
|---|---|
| Namespace | `csw-sensor` (older charts: `tetration`) |
| ServiceAccount | `csw-sensor` |
| ClusterRole | `csw-sensor` (read access to nodes, pods, services, namespaces) |
| Image | from Cisco's registry; mirrored to internal registry for production |
| DaemonSet name | `csw-sensor` |
| Configuration source | a Secret (`csw-sensor-config`) holding cluster URL, activation key, CA chain |

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

- [`../docs/`](../docs/) — prerequisites, sensor types, decision matrix, rollout strategy
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)
