# Operations — Air-Gapped and Isolated Environments

When workloads can't reach the internet, every install pattern
needs an internal mirror for packages, an internal registry for
container images, and an internal route to the CSW cluster. This
doc is the recipe.

---

## What "air-gapped" means here

Three flavours, in order of strictness:

| Flavour | Egress | Ingress |
|---|---|---|
| **Internet-restricted** | Outbound only via internal proxy / mirror | None |
| **Air-gapped, on-prem CSW** | None to internet; CSW cluster on the same internal network | None |
| **Strict air-gapped, no CSW path** | None to internet; CSW cluster also unreachable directly; data movement only via cross-domain transfer | None |

The first two are routine for CSW. The third requires Cisco's
**Air-Gap CSW** product variant — out of scope for this guide
beyond a pointer at the end.

---

## Pattern: internal mirrors for everything

The principle is to make every CSW deployment artefact reachable
*inside* your perimeter, so install jobs never need to touch the
internet.

### 1) Sensor RPM/DEB packages

- Download from CSW UI on a workstation that has internet
- Push into your internal Yum / DNF / APT repo (Satellite,
  Spacewalk, Pulp, or simple HTTP repo)
- Workloads install via standard `yum install tet-sensor` /
  `apt-get install tet-sensor`
- See [`../linux/03-package-repo-satellite.md`](../linux/03-package-repo-satellite.md)

### 2) Sensor MSI

- Download from CSW UI
- Place on a central SMB share or SCCM distribution point
- Deploy via SCCM / Intune / GPO startup script
- See [`../windows/03-sccm-deployment.md`](../windows/03-sccm-deployment.md)

### 3) K8s sensor container image

- Pull from Cisco's published registry on a connected
  workstation
- Tag and push to your internal container registry (Harbor,
  Artifactory, ECR, ACR, GCR)
- Override `image.repository` in the chart values or DaemonSet
  manifest
- See [`../kubernetes/01-daemonset-helm.md`](../kubernetes/01-daemonset-helm.md)

### 4) Helm chart

- For Helm-driven K8s installs: `helm pull` once, store as a
  tarball or push to an internal Helm repo / OCI registry

### 5) Cluster CA chain

- For on-prem CSW with internal PKI: bundle the CA into your
  install jobs alongside the package

### 6) Activation keys

- Generate per-tenant in CSW UI; store in your internal secrets
  manager (Vault, AWS Secrets Manager, Azure Key Vault); inject
  at install time

---

## Network path to the CSW cluster

Even in an air-gapped estate, the workloads must reach the CSW
cluster (otherwise no telemetry). The cluster sits inside your
perimeter; the workloads route to it directly. There's no
internet path involved.

If the workloads and the cluster are in different security zones
of the same DC:

- A firewall ticket permits TCP/443 from workload zones to the
  cluster zone
- No proxy is in the path (the cluster is on the same backbone)
- DNS resolves the cluster FQDN to its internal IP

If you absolutely cannot route between workload zones and the
cluster zone (some defence / regulated estates), Cisco offers
a **connector appliance** that bridges the two zones with an
outbound-only tunnel from the workload zone. Talk to your
account team about this pattern.

---

## Patching cadence in air-gapped estates

The internet-side update flow looks like:

```
Cisco publishes new sensor release
       │
       ▼
Connected workstation: download package
       │
       ▼
Internal artefact pipeline (scan, sign, version)
       │
       ▼
Internal Yum/APT/SMB/registry
       │
       ▼
Workload patching cycle (your existing patching tooling)
       │
       ▼
Sensor upgraded; CSW UI confirms version drift cleared
```

The cadence is whatever your standard patching cadence is
(monthly is typical). The CSW UI's *Manage → Agents → Upgrade*
page shows version drift across the fleet so you can track
catch-up rate after each push.

---

## Common gotchas in air-gapped estates

| Symptom | Cause | Fix |
|---|---|---|
| Install succeeds but sensor never registers | DNS doesn't resolve the cluster FQDN inside the air-gap | Add the cluster FQDN to internal DNS; or use IP + cluster cert SAN match |
| Sensor TLS handshake fails | Internal CA chain not present on the host | Push the cluster CA out via your standard CA-bundle distribution |
| K8s DaemonSet stuck in `ImagePullBackOff` | Cluster nodes can't pull from Cisco's registry | Mirror image to internal registry; override `image.repository` |
| Helm chart can't download | Chart repo URL not reachable | `helm pull` once on connected workstation; serve internally |
| Sensor versions drift further from cluster's latest | Patching cadence is slower than Cisco's release cadence | Document accepted drift; CSW supports a wide N-1 / N-2 window per release |

---

## Strict air-gapped (no path to the CSW cluster at all)

Out of scope for this guide. Cisco offers an **Air-Gap CSW**
product variant that runs the cluster entirely inside the
air-gap and accepts data via cross-domain transfer. Talk to your
account team if this is your environment.

---

## See also

- [`01-network-prereq.md`](./01-network-prereq.md)
- [`02-proxy.md`](./02-proxy.md)
- [`../linux/03-package-repo-satellite.md`](../linux/03-package-repo-satellite.md)
- [`../windows/03-sccm-deployment.md`](../windows/03-sccm-deployment.md)
- [`../kubernetes/02-daemonset-yaml.md`](../kubernetes/02-daemonset-yaml.md)
