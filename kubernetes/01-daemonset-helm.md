# Kubernetes — DaemonSet via Helm Chart *(community pattern)*

> **Important — Cisco does not publish a Helm chart for the CSW
> agent in the 4.0 documentation.** Cisco's documented K8s /
> OpenShift install path is the **Agent Script Installer** under
> *Manage → Workloads → Agents → Installer*, which generates the
> namespace, RBAC, ConfigMap / Secret, and DaemonSet directly.
> See the
> [Install Kubernetes or OpenShift Agents](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html)
> section.
>
> The pattern below is a **community / practitioner pattern** for
> shops standardised on Helm and GitOps that want the install
> declared as a chart. The values structure is modelled on what
> Cisco's Agent Script Installer produces, but the chart itself
> is not Cisco-published — chart names, values keys, and image
> paths in the snippets below are illustrative.
>
> If you're starting fresh, **prefer the Agent Script Installer**;
> capture its output (`kubectl get all -n tetration -o yaml`) as
> your GitOps source of truth.

> Working values file in [`./examples/helm/values.yaml`](./examples/helm/values.yaml).

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- Helm 3.10+ on the operator's workstation
- `kubectl` access to the target cluster with cluster-admin
  (or equivalent) for the initial install
- Outbound 443 from cluster nodes to the CSW cluster
- Image registry access — either the cluster nodes can pull from
  Cisco's published registry directly, or you've mirrored the
  image to your internal registry

---

## Step 1 — Generate values from the CSW UI

1. Log into the CSW UI
2. Navigate to *Manage → Agents → Install Agent*
3. Choose **Kubernetes** as the OS
4. Choose the **target scope**
5. Download the chart values file (or the chart manifest if your
   release ships it that way)

The downloaded values include:

- Cluster URL (`cluster.endpoint` or similar)
- Activation key (`cluster.activationKey`)
- CA chain (`cluster.caBundle`, base64-encoded)
- Sensor type and any release-specific parameters

Treat the activation key as a secret — keep it out of plain-text
Helm values that would land in a Git repo. See "Secret handling"
below for the production pattern.

---

## Step 2 — Mirror the image to your internal registry (recommended)

Production and air-gapped clusters should pull from your internal
registry, not Cisco's. Mirror once per agent release:

```bash
# Pull from Cisco's registry (workstation with internet)
docker pull <cisco-registry>/csw-sensor:3.x.y.z

# Tag and push to your internal registry
docker tag <cisco-registry>/csw-sensor:3.x.y.z \
  registry.internal.example.com/csw/sensor:3.x.y.z
docker push registry.internal.example.com/csw/sensor:3.x.y.z

# Override image.repository in your values:
#   image:
#     repository: registry.internal.example.com/csw/sensor
#     tag: 3.x.y.z
```

Cluster nodes need either ImagePullSecrets pointing at the
internal registry, or the registry is configured as a default
content trust source.

---

## Step 3 — Create the namespace with the privileged PSA label

```bash
kubectl create namespace csw-sensor

kubectl label namespace csw-sensor \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged
```

For OpenShift, see [04-openshift.md](./04-openshift.md) for the
SCC binding step in addition to PSA.

---

## Step 4 — Create the activation secret

Don't put the activation key in `values.yaml`. Create it as a
Kubernetes Secret in the namespace, then reference it from the
chart:

```bash
kubectl create secret generic csw-sensor-config \
  --namespace csw-sensor \
  --from-literal=activation_key='<key-from-CSW-UI>' \
  --from-literal=cluster_endpoint='csw.example.com' \
  --from-file=ca.pem=./ca.pem
```

In `values.yaml`, reference the secret by name instead of
inlining the key. Field names depend on the chart version:

```yaml
cluster:
  configFromSecret:
    name: csw-sensor-config
    activationKeyKey: activation_key
    endpointKey: cluster_endpoint
    caBundleKey: ca.pem
```

(If your chart version requires the values inline, use a
secrets-manager–rendered values file instead — sealed-secrets,
External Secrets Operator, Hashicorp Vault, AWS Secrets Manager
+ ESO, etc. — and never check the rendered file into Git.)

---

## Step 5 — Add the chart repo (if using a repo)

```bash
helm repo add csw <chart-repo-url>
helm repo update
helm search repo csw/sensor
```

For air-gapped clusters, fetch the chart once and store as an OCI
artefact in your internal registry, or as a tarball:

```bash
helm pull csw/sensor --version 3.x.y.z --untar
# Push the chart contents to your internal Helm repo or use
# `helm install --dry-run` from the local directory
```

---

## Step 6 — Install

```bash
helm install csw-sensor csw/sensor \
  --namespace csw-sensor \
  --version 3.x.y.z \
  --values ./values.yaml
```

The DaemonSet rolls out one pod per node. Watch:

```bash
kubectl get daemonset -n csw-sensor csw-sensor
kubectl get pods -n csw-sensor -l app=csw-sensor -o wide
```

Expected steady state: every node has one `csw-sensor-*` pod in
`Running` state. Pods that don't schedule are usually a tolerations
issue — check the node taints and the chart's
`tolerations:` value.

---

## Step 7 — Verify

```bash
# Pod status
kubectl -n csw-sensor get pods -o wide

# Pod logs from one of them
POD=$(kubectl -n csw-sensor get pods -l app=csw-sensor -o name | head -1)
kubectl -n csw-sensor logs "$POD" --tail 100

# Confirm the pod sees the host network namespace
kubectl -n csw-sensor exec -it "$POD" -- ss -tn | head -20
# Expected: connections from the node, not from the pod
```

In the **CSW UI** (*Manage → Agents → Software Agents*), each
cluster node should appear as a registered host within 1–2
minutes of the DaemonSet rollout.

---

## Step 8 — Day-2 patching cadence

Standard Helm lifecycle:

```bash
# Pull a new chart version
helm repo update

# Diff before applying (requires the helm-diff plugin)
helm diff upgrade csw-sensor csw/sensor \
  --namespace csw-sensor \
  --version 3.x.y+1.z \
  --values ./values.yaml

# Apply
helm upgrade csw-sensor csw/sensor \
  --namespace csw-sensor \
  --version 3.x.y+1.z \
  --values ./values.yaml
```

Helm's default rolling-update strategy on the DaemonSet means one
node's sensor at a time gets restarted, with PDB-aware behaviour.
For wave-based rollout across clusters, use Helm release names
per cluster (`csw-sensor-prod-cluster-A`, etc.) and apply per
cluster in sequence.

---

## Wave-based rollout across clusters

| Wave | Mechanism |
|---|---|
| Lab | Apply to lab cluster; wait 24 h |
| Stage | Apply to stage cluster |
| Prod canary | Apply to one prod cluster; observe a week |
| Prod rest | Apply across remaining prod clusters |

Argo CD / Flux ApplicationSets can drive this from a single Git
PR if you tag clusters by environment.

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `Pending` pods after `helm install` | PSA / PSP / SCC rejecting privileged pods | Confirm namespace label; check `kubectl describe pod` |
| `ImagePullBackOff` | Cluster nodes can't pull the image | Mirror to internal registry; add `imagePullSecrets:` |
| Pods running but no flows in CSW UI | Missing `hostNetwork`, `hostPID`, or volume mounts | Compare values to chart defaults; some charts have a `metricsOnly: true` switch that disables host-namespace mounts |
| Sensor pod CPU spike that never subsides | Per-node flow rate exceeds default profile | Adjust agent profile in CSW UI for that node group |
| DaemonSet not scheduling on tainted nodes (control-plane, GPU pools) | Missing tolerations | Add `tolerations:` matching the taints to the values file |
| Activation key in `values.yaml` checked into Git | Secret leak risk | Use Secret + chart `configFromSecret:` (or sealed-secrets) |

---

## See also

- [`./examples/helm/values.yaml`](./examples/helm/values.yaml)
- [`02-daemonset-yaml.md`](./02-daemonset-yaml.md) — air-gapped / no-Helm alternative
- [`03-eks-aks-gke.md`](./03-eks-aks-gke.md) — managed-K8s notes
- [`04-openshift.md`](./04-openshift.md)
- [`05-verification.md`](./05-verification.md)
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md)
