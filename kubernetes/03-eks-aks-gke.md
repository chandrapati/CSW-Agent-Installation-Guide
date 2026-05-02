# Kubernetes — EKS / AKS / GKE Notes

The Helm chart and raw-manifest patterns work across all
managed-K8s services. This doc is the tail of small,
service-specific things that catch teams off guard.

---

## EKS (AWS)

- **Pod IAM (IRSA).** If your sensor pod's ServiceAccount is
  annotated for IRSA, AWS-side IAM applies in addition to
  Kubernetes RBAC. The CSW sensor doesn't typically need AWS
  API access at runtime, so IRSA is usually unnecessary; if you
  do annotate, scope it minimally.
- **Bottlerocket nodes.** Bottlerocket has a read-only root FS
  and a different host-FS layout. Confirm host-path mounts in
  the chart values match the Bottlerocket paths
  (`/var/lib/containerd`, etc.) — Cisco's chart documentation
  for your release covers Bottlerocket if it's supported.
- **AL2 vs. AL2023 worker AMIs.** Both supported by the sensor
  in current releases; cross-check the matrix for kernel
  compatibility.
- **EKS Auto Mode.** Auto Mode manages the node lifecycle for
  you and runs a curated set of system pods. Confirm with Cisco
  that the sensor DaemonSet is on the Auto Mode allow-list for
  your release; if not, use a managed node group instead.
- **Fargate.** CSW sensor cannot run on Fargate-launched pods —
  Fargate doesn't expose the host kernel namespace. Workloads
  on Fargate need a different telemetry path (cloud connector,
  application-layer instrumentation).

---

## AKS (Azure)

- **Azure CNI vs. kubenet.** Both work; the sensor captures at
  the host network namespace either way. If you use Azure CNI
  Overlay or Cilium, confirm with Cisco's matrix.
- **Pod Identity / Workload Identity.** Same as EKS IRSA — not
  typically required for the sensor; scope minimally if used.
- **Azure Linux (CBL-Mariner) node pool.** Supported in current
  CSW releases; check the matrix for kernel compatibility.
- **Windows node pool.** AKS Windows node pools (Windows Server
  2019/2022 nodes) need the Windows DaemonSet variant of the
  sensor. Validate with Cisco; Windows-on-K8s sensor support
  has historically lagged Linux.
- **AKS automatic upgrades.** If the cluster is on auto-upgrade,
  node-image upgrades restart your sensor pods every cycle —
  fine, but plan for the disruption signal in monitoring.

---

## GKE (Google)

- **Standard vs. Autopilot.** Autopilot does not allow
  privileged pods and does not allow `hostNetwork: true`.
  **CSW sensor cannot run on Autopilot clusters.** Use Standard.
- **GKE Sandbox (gVisor).** gVisor sandboxes the workload pods;
  the sensor pod must NOT be sandboxed (it needs the real host
  kernel). Make sure the sensor's RuntimeClass remains the
  default, not `gvisor`.
- **Container-Optimized OS (COS).** GKE's default node OS.
  Supported by the sensor in current releases. The host paths
  for `/var/log` etc. are slightly different than RHEL — the
  Helm chart should auto-detect; for raw manifest, verify mount
  paths match COS.
- **GKE node auto-upgrade.** Same disruption pattern as AKS
  auto-upgrade — sensor pods restart per upgrade cycle.

---

## A few patterns that apply to all three

- **Tolerations for control-plane / system node pools.** If your
  cluster has dedicated control-plane node pools (uncommon on
  managed K8s but possible), add tolerations so the sensor
  schedules there too.
- **Per-node-pool image pull policy.** For cost / pull-rate
  reasons, set `imagePullPolicy: IfNotPresent` and pin the image
  tag. Avoid `Always` unless you intentionally pull every restart.
- **Node label selector for staged rollout across node pools.**
  Use `nodeSelector:` in the DaemonSet to roll out wave-style
  across labelled node pools (e.g.,
  `csw-sensor-wave: 1` on a few nodes first).
- **PodDisruptionBudget aware of cluster-autoscaler.** If
  Karpenter / Cluster Autoscaler is in play, a PDB on the sensor
  can prevent voluntary node removals; balance against the
  desire for elasticity.

---

## See also

- [`01-daemonset-helm.md`](./01-daemonset-helm.md)
- [`02-daemonset-yaml.md`](./02-daemonset-yaml.md)
- [`04-openshift.md`](./04-openshift.md)
- [`05-verification.md`](./05-verification.md)
- [`../agentless/01-aws-cloud-connector.md`](../agentless/01-aws-cloud-connector.md) — for Fargate / Autopilot workloads where the sensor can't run
