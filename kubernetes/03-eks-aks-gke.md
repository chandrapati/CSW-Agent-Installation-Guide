# Kubernetes — EKS / AKS / GKE Notes

Cisco's CSW 4.0 documentation gives Kubernetes / OpenShift
requirements for the Secure Workload agent, but it does **not**
publish separate EKS, AKS, or GKE install guarantees in this guide.
Use the **Agent Script Installer** first, then validate the managed
Kubernetes service, node OS, runtime, CNI, and Kubernetes version
against the Compatibility Matrix and TAC.

---

## EKS (AWS)

Do not assume every EKS compute mode can run the Secure Workload
DaemonSet. Cisco requires a privileged DaemonSet with host-level
access and host-path mounts. Validate at least:

- Kubernetes version and node OS in the Compatibility Matrix
- Container runtime and image-pull path to `CFG-SERVER-IP:443`
- CNI behavior against Cisco's enforcement requirements
- Whether the compute mode allows privileged DaemonSets and
  required host access

If a mode does not allow privileged DaemonSets or host access, use
Cisco-documented connector alternatives where applicable instead
of claiming the CSW pod agent is supported.

---

## AKS (Azure)

Do not assume support based only on "Kubernetes" support. Validate
the AKS Kubernetes version, node OS image, runtime, CNI mode, and
Windows node support against Cisco's matrix and TAC. The CSW 4.0
guide documents Windows worker-node prerequisites separately
(Windows Server 2019 / 2022, Kubernetes 1.27+, `containerd`, and
the required Microsoft host-process base image), so treat Windows
node pools as a separate validation item.

---

## GKE (Google)

Validate GKE Standard / Autopilot, node OS, sandboxing, runtime,
and CNI behavior with Cisco before rollout. The CSW pod agent needs
privileged host access; if a managed GKE mode does not permit that,
do not describe it as supported by this guide.

---

## A few patterns that apply to all three

- **Do not edit generated manifests blindly.** If you add
  tolerations, node selectors, affinity, or image-pull overrides,
  start from the Cisco-generated DaemonSet and document exactly
  what changed.
- **Use Cisco's CNI constraints.** Cisco 4.0 lists Calico 3.13
  as tested with specific Felix settings and describes the
  required behavior for other CNIs. Validate non-Calico modes with
  TAC before relying on enforcement.
- **Plan for managed-node churn.** Managed node upgrades restart
  DaemonSet pods. Treat that as an operational signal to monitor,
  not as an agent install capability claim.

---

## See also

- [`01-daemonset-helm.md`](./01-daemonset-helm.md)
- [`02-daemonset-yaml.md`](./02-daemonset-yaml.md)
- [`04-openshift.md`](./04-openshift.md)
- [`05-verification.md`](./05-verification.md)
- [`../agentless/01-aws-cloud-connector.md`](../agentless/01-aws-cloud-connector.md) — for Fargate / Autopilot workloads where the sensor can't run
