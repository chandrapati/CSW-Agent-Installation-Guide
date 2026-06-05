# Kubernetes — OpenShift

OpenShift / OKD adds **Security Context Constraints (SCC)** on
top of standard Kubernetes Pod Security Admission. The CSW sensor
is privileged and needs an SCC that permits privileged execution.
Cisco's documented CSW 4.0 install path is still the **Agent
Script Installer**. Use that first, then adjust OpenShift SCC
policy only when admission events show it is required.

---

## OpenShift-specific prerequisites

In addition to the items in
[`README.md`](./README.md):

- OpenShift 4.10+ (current support; check the matrix for
  older releases)
- Cluster-admin (or equivalent SCC-binding rights)
- The Cisco-documented `tetration` namespace created by the
  installer

---

## Step 1 — Run the Cisco Agent Script Installer

Generate the Kubernetes / OpenShift Agent Script Installer from
the CSW UI and run it with an `oc` context that has the required
cluster privileges. Cisco documents that Secure Workload entities
are created in the `tetration` namespace.

---

## Step 2 — If OpenShift blocks admission, bind the privileged SCC

```bash
# Replace <serviceaccount-from-generated-manifest> with the
# ServiceAccount created by the Cisco installer.
oc adm policy add-scc-to-user privileged \
  -z <serviceaccount-from-generated-manifest> \
  -n tetration
```

This is the OpenShift-specific step that the upstream Helm chart
does NOT do automatically. Without it, the DaemonSet pods will
fail admission.

To verify the binding:

```bash
oc adm policy who-can use scc privileged -n tetration
```

You should see the service account created by the Cisco installer
in the list.

---

## Step 3 — Do not hand-create activation Secrets

Do not create a guessed Secret with keys such as `activation_key`
or `ca.pem`. Use the Secret / ConfigMap produced by the Cisco
installer. If your organization wraps the generated manifests in
GitOps, copy the generated field names exactly.

---

## Step 4 — If using Helm / raw YAML internally

Cisco does not publish a Helm chart in the CSW 4.0 guide. If your
team wraps the Cisco-generated manifests in Helm or raw YAML, keep
the namespace, ServiceAccount, Secret / ConfigMap fields, image,
and RBAC from the generated installer output unless you have
validated a deliberate change.

---

## Step 5 — Verify

```bash
# Pods must be Running, one per node
oc get ds -n tetration
oc get pods -n tetration -o wide

# If any pod fails admission, the events explain why:
oc describe pod -n tetration <pending-pod-name>
# Look for "unable to validate against any security context constraint"
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Pods fail: `unable to validate against any security context constraint: provider "privileged"` | SCC not bound to ServiceAccount | Bind `privileged` SCC to Cisco-generated ServiceAccount in `tetration` namespace |
| Pods fail SCC (no provider listed) | Pod requests exceed SCC | Compare pod spec to generated manifest; adjust only after validation |
| Internal Helm chart missing SCC binding | Chart drift from Cisco manifest | Re-bind SCC to chart ServiceAccount |
| Sensor pods restart on cluster upgrade | Machine-config rotation | Expected; monitor as known cause |
| No flows despite Running pods | Wrong Secret / cluster URL in ConfigMap | Re-run Agent Script Installer; apply fresh Secret |
| `ImagePullBackOff` on OpenShift | Registry pull from CSW cluster blocked | Mirror image to internal OpenShift registry |

Full troubleshooting: [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md) · [`05-verification.md`](./05-verification.md)

---

## See also

- [`01-daemonset-helm.md`](./01-daemonset-helm.md)
- [`02-daemonset-yaml.md`](./02-daemonset-yaml.md)
- [`05-verification.md`](./05-verification.md)
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)
- OpenShift docs: *Managing Security Context Constraints* (link inside your cluster's local docs)
