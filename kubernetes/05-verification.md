# Kubernetes — Verification

Post-install checklist for K8s sensor deployments. Pair these
checks with the **CSW UI** (*Manage → Agents → Software Agents*).

---

## Five-minute health check

```bash
# 1. DaemonSet rollout complete
kubectl get ds -n csw-sensor csw-sensor
# DESIRED == CURRENT == READY == UP-TO-DATE; no MISCONFIGURED

# 2. One pod per node, all Running
kubectl get pods -n csw-sensor -l app=csw-sensor -o wide

# 3. Recent logs without ERROR / FATAL
POD=$(kubectl -n csw-sensor get pods -l app=csw-sensor -o name | head -1)
kubectl -n csw-sensor logs "$POD" --tail 50

# 4. Sensor can see host network namespace
kubectl -n csw-sensor exec "$POD" -- ss -tn 2>/dev/null | head -5
# Expect connections from the node IP (because hostNetwork: true)

# 5. CSW UI: each node appears as a registered host
```

If 1–4 pass and 5 reports the node, the install is healthy.

---

## Detailed verification

### DaemonSet schedule

```bash
# Per-node pod placement
kubectl get pods -n csw-sensor -l app=csw-sensor \
  -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase

# Nodes that should have the sensor (i.e., everything matching the
# DaemonSet's nodeSelector / tolerations)
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# Compare. Any node with the sensor's tolerations but no sensor pod
# is an unhealthy gap.
```

### Pod-level health

```bash
POD=$(kubectl -n csw-sensor get pods -l app=csw-sensor -o name | head -1)

# Resource consumption
kubectl top pod -n csw-sensor "$POD"

# Pod definition (verify hostNetwork, hostPID, privileged)
kubectl get -n csw-sensor "$POD" -o jsonpath='{.spec.hostNetwork}{"\n"}{.spec.hostPID}{"\n"}{.spec.containers[0].securityContext.privileged}{"\n"}'
# Expected: true / true / true

# Mounted host paths
kubectl get -n csw-sensor "$POD" -o jsonpath='{range .spec.volumes[*]}{.name}{"\t"}{.hostPath.path}{"\n"}{end}'
# Expected: at least /proc, /sys, /var/log entries
```

### Connectivity to the CSW cluster

From inside the sensor pod:

```bash
kubectl -n csw-sensor exec "$POD" -- /bin/sh -c \
  "curl -s -o /dev/null -w 'HTTP_CODE: %{http_code}\nCONNECT: %{time_connect}s\nTOTAL: %{time_total}s\n' https://csw.example.com:443/"
```

Expect `HTTP_CODE: 4xx` (the cluster URL doesn't have a default
web page; what you're checking is that TLS handshake completes
and a response was returned).

### Time sync on nodes

The sensor pod uses the host clock (because `hostNetwork: true`
implies host-namespace time too):

```bash
# Spot-check a node's NTP status
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
# Whatever your usual node-debug pattern is — `oc debug node`,
# kubectl-debug node, or SSH into the node:
kubectl debug node/"$NODE" -it --image=busybox -- date -u
# Compare with: date -u (on your workstation)
# Acceptable skew: < 5 seconds
```

### CSW UI cross-check

1. *Manage → Agents → Software Agents*
2. Filter by `cluster_name == <your-k8s-cluster-name>` or by
   the node's IP/hostname
3. Each node from `kubectl get nodes` should appear with status
   *Running*
4. Click into one node; *Inventory tags* should include
   Kubernetes labels (namespace, deployment, service for the
   pods the node hosts)
5. *Investigate → Flows*; filter by a known pod's IP. Within
   2 minutes you should see flows attributed to that pod's
   namespace + deployment

---

## Common findings

### "DaemonSet shows N/N ready but only some nodes appear in CSW"

- Confirm time sync on the missing nodes (clock skew breaks TLS)
- Confirm outbound 443 from those node IPs to the cluster (some
  estates have node-pool–specific egress rules)
- Tail the sensor pod log on the missing node specifically

### "Pods Running but UI shows them as Not Active"

- The sensor pod is healthy at the K8s level but isn't
  registering with the cluster. Causes:
  - Activation key in the Secret is wrong / expired
  - CA chain mismatch (on-prem cluster)
  - Egress proxy in the way; configure proxy in the values

### "Flows show source as the node IP, not the pod IP"

- The sensor sees the host network namespace, where pod traffic
  has been NAT'd to the node IP **only if** the pod is using
  `hostNetwork: true` itself or going out via SNAT (typical for
  egress traffic). For pod-to-pod traffic inside the cluster
  the sensor sees pod IPs as long as the CNI doesn't NAT them
  (most CNIs don't). If you're seeing pod-to-external traffic
  attributed to the node IP, that's normal — the SNAT happened
  at egress.

### "Sensor pod restarting every few minutes"

- Look at `kubectl describe pod` for the restart reason
- Check resource limits — the sensor under high flow load may
  exceed memory limits in the chart defaults; raise them
- Check kernel log on the host (`dmesg | grep -i tet`) for
  module-load issues

---

## See also

- [`../linux/08-verification.md`](../linux/08-verification.md) — broader verification reference (the host-side patterns apply)
- [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)
