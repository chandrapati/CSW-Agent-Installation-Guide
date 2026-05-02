# Cloud — VM Installation Methods

Patterns for installing the CSW agent on cloud VMs (AWS EC2,
Azure VMs, GCP Compute Engine). Two operating models:

- **First-boot install** — embed the agent install in
  `user_data` / `custom_data` / startup script. Works for any IaC
  tool. Best for environments with frequent VM churn but a small
  set of base OS images.
- **Image baked** — install the agent into a Golden AMI / Compute
  Gallery image / GCE custom image during the build phase. Every
  VM launched from the image has the agent already running.
  Best for fleet scale; the most operationally durable pattern at
  cloud scale.

> **First decide: agent or Cloud Connector?** If the cloud account
> isn't where you want every VM to carry an agent, the agentless
> Cloud Connector ([`../agentless/`](../agentless/)) gives you
> inventory + flow-log visibility without per-VM install. This
> folder is for the *agent* path.

---

## Methods in this folder

| # | Method | Best for | Doc |
|---|---|---|---|
| 01 | AWS EC2 `user_data` | New EC2 instances, any IaC tool | [01-aws-userdata.md](./01-aws-userdata.md) |
| 02 | Azure `custom_data` / cloud-init | New Azure VMs, any IaC tool | [02-azure-customdata.md](./02-azure-customdata.md) |
| 03 | GCP startup script | New GCE instances, any IaC tool | [03-gcp-startup-script.md](./03-gcp-startup-script.md) |
| 04 | Terraform examples | Multi-cloud IaC pipelines | [04-terraform.md](./04-terraform.md) |
| 05 | Golden AMI (Packer) | AWS at fleet scale | [05-golden-ami.md](./05-golden-ami.md) |
| 06 | Azure Compute Gallery image | Azure at fleet scale | [06-azure-vm-image.md](./06-azure-vm-image.md) |

---

## Cloud-specific prerequisites

The general prerequisites in
[`../docs/01-prerequisites.md`](../docs/01-prerequisites.md) all
apply. A few cloud-specific additions:

### Outbound 443 to the cluster

- **AWS**: VPC needs an Internet Gateway (public subnet) or a NAT
  Gateway (private subnet) for outbound 443. For SaaS clusters,
  the destination is a public Cisco hostname; for on-prem
  clusters, ensure VPN / Direct Connect to the cluster's network.
- **Azure**: Default outbound is allowed unless an NSG or Azure
  Firewall blocks it. For private endpoints to a SaaS cluster,
  use the cluster vendor's documented private link pattern (if
  available).
- **GCP**: Default network has outbound; Cloud NAT for instances
  in private subnets. Confirm VPC firewall rules allow egress on
  443.

### IMDSv2 / metadata service

When agent install scripts need to fetch payloads from cloud
storage (S3 / Azure Blob / GCS), they typically authenticate via
the instance metadata service:

- **AWS**: Always use **IMDSv2** (token-based). IMDSv1 is a
  documented security risk; require IMDSv2 in your account
  baseline. Agent install scripts should use the IMDSv2 token
  flow:
  ```bash
  TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id
  ```
- **Azure**: IMDS at `http://169.254.169.254/metadata/instance`
  with header `Metadata: true`.
- **GCP**: Metadata at `http://metadata.google.internal/computeMetadata/v1/`
  with header `Metadata-Flavor: Google`.

### Cloud-provider package mirror

For air-gapped patterns within a cloud account, mirror the CSW
agent packages into:

- **AWS**: a private S3 bucket (with VPC endpoint for S3) or
  CodeArtifact private repo
- **Azure**: a private Blob Storage container (with private
  endpoint) or Azure Artifacts feed
- **GCP**: a private GCS bucket (with VPC Service Controls) or
  Artifact Registry

The Terraform examples in [`04-terraform.md`](./04-terraform.md)
show the IAM-grant patterns.

---

## When to bake the agent vs. install at first boot

| Scenario | Pattern | Why |
|---|---|---|
| Steady-state fleet, infrequent base-image updates | **Bake into image** | Zero-touch on launch; agent always present |
| Frequent base-image updates (weekly hardened images) | **Bake into image** | Image pipeline is already running; add a sensor-install step |
| New cloud account, no existing image pipeline | **First-boot install** | Lower start-up cost; can revisit after image pipeline matures |
| Spot / preemptible / very short-lived instances | **Bake into image** | First-boot install adds VM startup latency; baking removes it |
| Instances launched via Auto Scaling groups | Either; bake preferred | Auto-scale events benefit from sub-minute readiness |
| Instances managed by Karpenter / Cluster Autoscaler (K8s nodes) | **Bake into the node image** | Avoid sensor install on every node-pool scaling event |
| One-off or developer-spun VMs in non-prod | **First-boot install** | Acceptable startup overhead; no image pipeline needed |

The pragmatic approach: **first-boot install in early days; bake
into the image once the first wave is stable**.

---

## Sensor type for cloud workloads

- Use **Deep Visibility / Enforcement** for any workload you
  manage with the agent. Same as on-prem.
- Use the **Cloud Connector** ([`../agentless/`](../agentless/))
  *in addition to* the host agent for:
  - Inventory of cloud workloads not in your management scope
    (sandbox accounts, partner-shared accounts)
  - Flow-log-tier visibility across the whole VPC for traffic
    that doesn't traverse a workload running an agent

The two are complementary, not exclusive.

---

## See also

- [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- [`../docs/02-sensor-types.md`](../docs/02-sensor-types.md)
- [`../docs/03-decision-matrix.md`](../docs/03-decision-matrix.md)
- [`../agentless/`](../agentless/) — Cloud Connectors
- [`../kubernetes/`](../kubernetes/) — for K8s-on-cloud deployments
- [`../operations/02-proxy-configuration.md`](../operations/02-proxy-configuration.md)
