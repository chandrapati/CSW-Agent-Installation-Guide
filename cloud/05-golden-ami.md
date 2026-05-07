# AWS — Golden AMI (Packer)

The "best" pattern at scale. Bake the CSW agent into a hardened
base AMI during the image build phase. Every new EC2 instance
launched from the AMI has the agent already installed, registered,
and reporting telemetry within seconds of boot. No first-boot
install latency, no `user_data` payload, no per-launch IAM grant
to fetch the package.

> The Azure analogue is **Compute Gallery image** —
> [06-azure-vm-image.md](./06-azure-vm-image.md). The GCP
> analogue is **GCE custom image**.

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- HashiCorp Packer 1.9+ installed in your build environment
- An AWS account where you have permission to:
  - Launch a temporary builder EC2 instance
  - Write the resulting AMI to your AMI registry account
  - Read the CSW agent payload from S3 (Packer's IAM role)
- The CSW agent package staged in S3 (or accessible to the Packer
  builder via your usual file mechanism)
- A base AMI to start from — typically your org's CIS-hardened
  base AMI, not a bare public AMI

---

## Step 1 — Choose the activation pattern

Two patterns; pick before authoring the Packer template:

### Pattern X — Activate at first boot

Bake the agent **binaries** in; defer **activation** to first
boot. The image is generic; activation per instance is driven by
`user_data` (the activation key from Secret Manager / SSM /
Key Vault).

- **Pro:** one image works for any scope; the per-instance
  activation can target different scopes
- **Pro:** the image doesn't carry an embedded activation key
  (smaller blast radius if the AMI leaks)
- **Con:** still depends on the Cisco golden-image behavior being
  correct for your release and image pipeline.

### Pattern Y — Activate during image build

Activate the agent during Packer's provisioning, then create the
image. Every instance from this AMI registers under the same
scope automatically.

- **Pro:** zero first-boot work; agent is already known to the
  cluster the moment the instance starts
- **Con:** one image per scope (or you accept that all instances
  from this image start in the same scope and get re-labelled
  later)
- **Con:** the generated installer embeds activation material —
  treat the AMI and build logs as sensitive artefacts accordingly.

**Recommendation.** Pattern X is more flexible and the safer
default. Pattern Y is appropriate when you have a clean
per-scope image-build pipeline (e.g., one Packer build per
business unit) and the AMI distribution is tightly controlled.

The Packer template below shows Pattern X. The deltas for
Pattern Y are noted at the end.

---

## Step 2 — Author the Packer template

### `golden-ami-csw.pkr.hcl`

```hcl
packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.2"
    }
  }
}

variable "region"            { default = "us-east-1" }
variable "base_ami_owner"    { default = "amazon" }       # public; replace with your org account ID
variable "base_ami_name"     { default = "al2023-ami-*-x86_64" }
variable "csw_installer_s3_uri" { default = "s3://internal-csw-agents/linux/tetration_linux_installer.sh" }
variable "csw_agent_version" { default = "3.x.y.z" }

source "amazon-ebs" "rhel9_csw" {
  region          = var.region
  instance_type   = "t3.medium"
  ssh_username    = "ec2-user"
  ami_name        = "internal-rhel9-csw-${var.csw_agent_version}-{{ timestamp }}"
  ami_description = "RHEL 9 with CSW sensor v${var.csw_agent_version} pre-installed"

  source_ami_filter {
    filters = {
      name                = var.base_ami_name
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = [var.base_ami_owner]
    most_recent = true
  }

  iam_instance_profile = "packer-builder-csw"   # has s3:GetObject for the agent bucket

  # IMDSv2 only on instances launched from this AMI
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  ami_users = ["111111111111", "222222222222"]   # AWS account IDs allowed to launch this AMI
  tags = {
    Name              = "rhel9-csw-${var.csw_agent_version}"
    csw_agent_version = var.csw_agent_version
    base_ami_lineage  = var.base_ami_name
  }
}

build {
  sources = ["source.amazon-ebs.rhel9_csw"]

  # Patch baseline first
  provisioner "shell" {
    inline = [
      "sudo dnf upgrade -y",
      "sudo dnf install -y kernel-headers-$(uname -r) || true",   # required for the kernel module compile
    ]
  }

  # Install the CSW agent using Cisco's golden-image flow.
  provisioner "shell" {
    inline = [
      "set -euxo pipefail",
      "sudo aws s3 cp ${var.csw_installer_s3_uri} /tmp/tetration_linux_installer.sh",
      "sudo chmod 700 /tmp/tetration_linux_installer.sh",
      "sudo bash /tmp/tetration_linux_installer.sh --golden-image",
      "sudo rm -f /tmp/tetration_linux_installer.sh",
    ]
  }

  # Sanity check the build
  provisioner "shell" {
    inline = [
      "rpm -q tet-sensor",
      "ls -la /etc/tetration/",
      "systemctl status csw-agent || true",
    ]
  }
}
```

The instance's `user_data` should not write `sensor.conf` or
unmask legacy service names. Cisco documents `--golden-image` as
the control for image/template builds; rely on the generated
installer behavior for your release and verify clones register
correctly before promoting the AMI.
appropriately.

---

## Step 3 — Build the image

```bash
packer init golden-ami-csw.pkr.hcl
packer fmt -recursive .
packer validate \
  -var "csw_agent_version=3.10.1.45" \
  golden-ami-csw.pkr.hcl
packer build \
  -var "csw_agent_version=3.10.1.45" \
  golden-ami-csw.pkr.hcl
```

Output includes the new AMI ID. Capture it in your AMI registry
(SSM Parameter Store, an internal AMI catalogue, or an
`amazon-ami-management`-style automation).

---

## Step 4 — Reference the image in launch templates / Terraform

```hcl
data "aws_ami" "internal_rhel9_csw" {
  most_recent = true
  owners      = ["111111111111"]   # the build account
  filter {
    name   = "tag:csw_agent_version"
    values = ["3.10.1.45"]
  }
}

resource "aws_launch_template" "web" {
  name_prefix   = "web-"
  image_id      = data.aws_ami.internal_rhel9_csw.id
  instance_type = "t3.medium"

  iam_instance_profile {
    arn = aws_iam_instance_profile.web.arn   # has ssm:GetParameter for the activation key
  }

  metadata_options {
    http_tokens = "required"
    instance_metadata_tags = "enabled"   # required so the first-boot script can read instance tags
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name              = "web"
      csw_scope         = "prod:web-tier"
      csw_scope_param   = "/csw/activation-key/prod-web"
    }
  }
}
```

---

## Step 5 — Image lifecycle

A working image lifecycle keeps the AMI fresh:

| Cadence | Action |
|---|---|
| Monthly (or on CSW agent release) | Re-run Packer build with the new agent version; publish new AMI |
| Quarterly | Re-baseline against the latest hardened base AMI; update Packer template |
| Per security patch window | Patch baseline OS within the Packer build (`dnf upgrade -y`); re-publish |
| Always | Tag old AMIs with a deprecation date; deregister after a grace period |

Tools:

- **EC2 Image Builder** (managed Packer-equivalent) for orgs
  that prefer AWS-native
- **packer-cleanup** scripts to deregister AMIs older than N days
- **AMI registry / catalogue** (SSM Parameter Store with the
  current AMI ID per role) so launch templates can `data
  "aws_ssm_parameter"` the latest

---

## Pattern Y — activate at build time (deltas)

If you want the AMI to come up already registered (no first-boot
work, no per-instance activation):

In the Packer template, replace the "disable + first-boot service"
block with:

```hcl
provisioner "shell" {
  inline = [
    "set -euxo pipefail",
    "ACTIVATION_KEY=$(aws ssm get-parameter --name /csw/activation-key/prod-web \\",
    "    --with-decryption --region ${var.region} --query Parameter.Value --output text)",
    "sudo bash -c \"cat > /etc/tetration/sensor.conf\" <<EOF",
    "ACTIVATION_KEY=$ACTIVATION_KEY",
    "SCOPE=prod:web-tier",
    "EOF",
    "sudo chmod 640 /etc/tetration/sensor.conf",
    "sudo systemctl enable csw-agent",
    # Don't start csw-agent during build — let it activate at instance launch
    # (otherwise the build instance also registers, polluting the cluster)
  ]
}
```

Treat the resulting AMI as **sensitive** because it carries an
activation key. Restrict `ami_users` / sharing accordingly.

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Packer build registers the agent against the cluster | `csw-agent` started during build | Mask the service before the build provisioner starts (see Pattern X above); use Pattern X instead of Y |
| Image build succeeds but instances launched from it never start `csw-agent` | `csw-first-boot.service` failed silently | Check `agent logs` on a launched instance; usually a missing tag or SSM permission |
| AMI reaches consumer accounts but `aws ssm get-parameter` fails | The launching account can't read the activation key parameter | Move the parameter to the launching account's SSM (or use cross-account parameter access via Resource Access Manager) |
| Sensor inventory shows the build instance as a registered host | Same as gotcha 1 | Mask `csw-agent` during build; deregister the build instance from CSW UI |
| Image build fails on `kernel-headers` mismatch | Build instance kernel doesn't match the headers package | Pin the kernel during the build (`dnf install kernel-X.Y.Z-N`); or run `dnf upgrade -y && reboot` before installing the agent |

---

## When this is the right method

- **Cloud at scale** — every fleet of more than a few hundred
  instances benefits from baking
- **Spot / preemptible / very short-lived instances** — first-boot
  install latency is unacceptable for those
- **Orgs with an existing image-build pipeline** — adding the
  CSW step is incremental cost
- **Regulated environments** that require base-image attestation
  — bake into the attested image

## When this is NOT the right method

- **No image-build pipeline yet** — start with first-boot
  install, build the image pipeline next
- **One-off / dev-spun instances** — first-boot install is fine
- **Frequent CSW agent version changes** that out-pace your image
  rebuild cadence — first-boot can pick up newer packages without
  a new image

---

## See also

- Static Packer example intentionally removed until it can be
  rebuilt around Cisco's `--golden-image` installer flow.
- [`./examples/cloud-init/aws-csw-rhel9.sh`](./examples/cloud-init/aws-csw-rhel9.sh) — first-boot script that pairs with Pattern X
- [`01-aws-userdata.md`](./01-aws-userdata.md) — first-boot alternative
- [`04-terraform.md`](./04-terraform.md) — Terraform that consumes the AMI
- [`06-azure-vm-image.md`](./06-azure-vm-image.md) — Azure analogue
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md) — image-rebuild as the upgrade vehicle
