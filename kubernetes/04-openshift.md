# Kubernetes — OpenShift

OpenShift / OKD adds **Security Context Constraints (SCC)** on
top of standard Kubernetes Pod Security Admission. The CSW sensor
is privileged and needs an SCC that permits privileged execution.
Everything else (Helm chart, raw manifest, verification) follows
the upstream pattern.

---

## OpenShift-specific prerequisites

In addition to the items in
[`README.md`](./README.md):

- OpenShift 4.10+ (current support; check the matrix for
  older releases)
- Cluster-admin (or equivalent SCC-binding rights)
- A namespace dedicated to the sensor (don't reuse `default` or
  any user-workload namespace)

---

## Step 1 — Create the namespace + ServiceAccount

```bash
oc new-project csw-sensor

oc create serviceaccount csw-sensor -n csw-sensor
```

---

## Step 2 — Bind the privileged SCC to the ServiceAccount

```bash
oc adm policy add-scc-to-user privileged -z csw-sensor -n csw-sensor
```

This is the OpenShift-specific step that the upstream Helm chart
does NOT do automatically. Without it, the DaemonSet pods will
fail admission.

To verify the binding:

```bash
oc adm policy who-can use scc privileged -n csw-sensor
```

You should see `system:serviceaccount:csw-sensor:csw-sensor` in
the list.

---

## Step 3 — Create the activation Secret

Same as upstream:

```bash
oc create secret generic csw-sensor-config \
  --namespace csw-sensor \
  --from-literal=cluster_endpoint='csw.example.com' \
  --from-literal=activation_key='<key-from-CSW-UI>' \
  --from-file=ca.pem=./ca.pem
```

---

## Step 4 — Install via Helm or raw manifest

### Option A: Helm

OpenShift supports Helm 3.x via the OpenShift Helm Operator (or
the `helm` CLI installed by the operator). Same as
[01-daemonset-helm.md](./01-daemonset-helm.md):

```bash
helm install csw-sensor csw/sensor \
  --namespace csw-sensor \
  --version 3.x.y.z \
  --values ./values.yaml \
  --set serviceAccount.name=csw-sensor \
  --set serviceAccount.create=false   # we already created it for SCC binding
```

### Option B: Raw manifest

Same as [02-daemonset-yaml.md](./02-daemonset-yaml.md). Edit the
DaemonSet's `serviceAccountName: csw-sensor` (already done in the
example manifest) and apply.

---

## Step 5 — Verify

```bash
# Pods must be Running, one per node
oc get ds -n csw-sensor csw-sensor
oc get pods -n csw-sensor -o wide

# If any pod fails admission, the events explain why:
oc describe pod -n csw-sensor <pending-pod-name>
# Look for "unable to validate against any security context constraint"
```

---

## OpenShift-specific gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Pods fail with `unable to validate against any security context constraint: provider "privileged"` | SCC not bound to the ServiceAccount | Re-run `oc adm policy add-scc-to-user privileged -z csw-sensor -n csw-sensor` |
| Pods fail with `unable to validate against any security context constraint` (no provider listed) | No SCC matches the pod's requested capabilities | The pod requests something not on `privileged` SCC; check the pod spec, usually a non-default capability or volume |
| Sensor installs but reports no flows from pods running with `runAsNonRoot` enforcement | OpenShift's `restricted-v2` SCC randomises UIDs; the sensor still sees flows because it captures at the host network namespace, not the pod | This usually isn't an issue — verify with `oc exec` into a sensor pod and check `ss -tn` shows host connections |
| Helm chart applies but the `serviceaccount` it creates doesn't have the SCC binding | The chart auto-created a ServiceAccount with a name you didn't bind | Set `serviceAccount.create=false` and `serviceAccount.name=csw-sensor` in values; or re-bind with the chart-created name |
| OpenShift cluster updates restart sensor pods every cycle | Expected behaviour from machine-config rotation | Make sure observability picks up the disruption as a *known cause*, not a sensor failure |

---

## See also

- [`01-daemonset-helm.md`](./01-daemonset-helm.md)
- [`02-daemonset-yaml.md`](./02-daemonset-yaml.md)
- [`05-verification.md`](./05-verification.md)
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)
- OpenShift docs: *Managing Security Context Constraints* (link inside your cluster's local docs)
