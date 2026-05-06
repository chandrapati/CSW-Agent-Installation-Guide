# Kubernetes — DaemonSet via Raw Manifest *(community pattern)*

> **Cisco-documented method is the Agent Script Installer.** See
> [Install Kubernetes or OpenShift Agents](https://www.cisco.com/c/en/us/td/docs/security/workload_security/secure_workload/user-guide/4_0/cisco-secure-workload-user-guide-on-prem-v40/deploy-software-agents.html).
> This page covers a **community / practitioner pattern** for
> air-gapped or no-Helm shops that prefer to manage the install
> as raw YAML. The manifest content is modelled on what the
> Agent Script Installer creates; treat the values, image paths,
> and namespace as illustrative.

For air-gapped clusters and no-Helm shops. Same end-state as the
Helm chart pattern — one privileged agent pod per node — but
declared as a single hand-managed YAML instead of a chart.

> Working manifest in [`./examples/manifest/daemonset.yaml`](./examples/manifest/daemonset.yaml).

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- `kubectl` access with cluster-admin
- The CSW sensor image **mirrored to your internal registry**
  (this method is most often used precisely because the cluster
  can't reach Cisco's registry directly)
- The activation key, cluster URL, and (on-prem cluster) CA chain
  available locally for placement into a Secret

---

## Step 1 — Mirror the image

Same as [01-daemonset-helm.md](./01-daemonset-helm.md) Step 2.
Cluster nodes need a path to the image; for air-gapped clusters
that's the internal registry.

---

## Step 2 — Create the namespace + Secret + ServiceAccount + RBAC

```bash
kubectl create namespace csw-sensor

kubectl label namespace csw-sensor \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged

# Secret holding cluster URL, activation key, CA chain
kubectl create secret generic csw-sensor-config \
  --namespace csw-sensor \
  --from-literal=cluster_endpoint='csw.example.com' \
  --from-literal=activation_key='<key-from-CSW-UI>' \
  --from-file=ca.pem=./ca.pem
```

ServiceAccount + ClusterRole + Binding (apply the file from the
example folder):

```bash
kubectl apply -f examples/manifest/rbac.yaml
```

---

## Step 3 — Apply the DaemonSet manifest

Edit [`./examples/manifest/daemonset.yaml`](./examples/manifest/daemonset.yaml)
to reference your mirrored image:

```yaml
spec:
  template:
    spec:
      containers:
        - name: csw-sensor
          image: registry.internal.example.com/csw/sensor:3.x.y.z
```

Apply:

```bash
kubectl apply -n csw-sensor -f examples/manifest/daemonset.yaml
```

Watch the rollout:

```bash
kubectl -n csw-sensor get ds csw-sensor -w
kubectl -n csw-sensor get pods -o wide
```

Expected: `DESIRED == CURRENT == READY` matches your node count
within 1–2 minutes.

---

## Step 4 — Verify

Same as [05-verification.md](./05-verification.md). The cluster
nodes should appear in the CSW UI within minutes of pods reaching
`Running` state.

---

## Step 5 — Day-2 patching cadence

In a no-Helm world, upgrades are an `image:` field bump:

```bash
# Update the manifest with the new image tag
sed -i 's|csw/sensor:3.x.y.z|csw/sensor:3.x.y+1.z|' examples/manifest/daemonset.yaml

# Apply
kubectl apply -n csw-sensor -f examples/manifest/daemonset.yaml

# Watch the rolling update
kubectl -n csw-sensor rollout status ds/csw-sensor
```

Add a PodDisruptionBudget if your DaemonSet is on nodes where
disruption needs to be controlled:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: csw-sensor
  namespace: csw-sensor
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: csw-sensor
```

---

## When this is the right method

- **Air-gapped clusters** where the chart repo isn't reachable
- **Clusters where Helm is not permitted** (some regulated /
  classified environments)
- **GitOps shops that prefer raw YAML over chart rendering** —
  Argo CD and Flux both consume raw manifests cleanly

## When the Helm chart is preferable

- Clusters with internet egress and standard Helm tooling
- Multi-cluster fleets where chart values can templatise
  per-cluster differences (region, scope, image version) cleanly
- Whenever you want Cisco's release-cycle hardening of the chart
  rather than maintaining the manifest yourself

---

## See also

- [`./examples/manifest/daemonset.yaml`](./examples/manifest/daemonset.yaml)
- [`./examples/manifest/rbac.yaml`](./examples/manifest/rbac.yaml)
- [`01-daemonset-helm.md`](./01-daemonset-helm.md)
- [`03-eks-aks-gke.md`](./03-eks-aks-gke.md)
- [`04-openshift.md`](./04-openshift.md)
- [`05-verification.md`](./05-verification.md)
