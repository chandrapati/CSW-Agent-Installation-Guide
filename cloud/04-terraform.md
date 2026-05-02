# Cloud — Terraform Examples

Terraform-driven CSW agent installation across AWS, Azure, and
GCP. The patterns below combine the per-cloud first-boot install
docs with the IaC layer that most production cloud estates run.

> Runnable Terraform in
> [`./examples/terraform/`](./examples/terraform/).

---

## Pattern: per-cloud module wraps the install logic

The high-leverage pattern is a small Terraform module per cloud
that:

1. Renders the cloud-init / startup script (with the right
   activation key and scope per environment)
2. Wires the right IAM policy / managed identity / service
   account so the VM can read the agent payload from cloud
   storage
3. Exports outputs the consumer can use (e.g.,
   `csw_metadata` for CMDB integration)

A consumer module then calls one of these per VM (or per VM
Scale Set / Auto Scaling Group / Managed Instance Group):

```hcl
module "vm_csw" {
  source = "../../modules/csw-aws-vm"

  name             = "prod-web-01"
  ami              = data.aws_ami.al2023.id
  instance_type    = "t3.medium"
  subnet_id        = aws_subnet.private.id
  iam_role_arn     = aws_iam_role.web_with_csw.arn
  csw_scope        = "prod:web-tier"
  csw_cluster_fqdn = "csw.example.com"
  csw_agent_pkg    = "s3://internal-csw-agents/linux/el9/tet-sensor-3.10.1.45-1.el9.x86_64.rpm"
}
```

---

## AWS — minimal Terraform example

### `aws-userdata.tf`

```hcl
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "csw_scope" {
  description = "CSW scope label, e.g. prod:web-tier"
  type        = string
}

variable "csw_cluster_fqdn" {
  description = "CSW cluster FQDN — used in the verification step only"
  type        = string
}

variable "csw_agent_s3_uri" {
  description = "s3:// URI to the agent .rpm/.deb"
  type        = string
}

variable "csw_ca_s3_uri" {
  description = "s3:// URI to the cluster CA chain"
  type        = string
}

variable "ssm_activation_key_name" {
  description = "Name of the SSM Parameter holding the CSW activation key"
  type        = string
}

# IAM role allowing the instance to pull the agent and read SSM
data "aws_iam_policy_document" "instance_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "csw_instance" {
  name               = "csw-instance-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
}

data "aws_iam_policy_document" "csw_instance" {
  statement {
    sid       = "ReadAgentPayload"
    actions   = ["s3:GetObject"]
    resources = [
      replace(var.csw_agent_s3_uri, "s3://", "arn:aws:s3:::"),
      replace(var.csw_ca_s3_uri,    "s3://", "arn:aws:s3:::"),
    ]
  }
  statement {
    sid       = "ReadActivationKey"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:*:*:parameter${var.ssm_activation_key_name}"]
  }
}

resource "aws_iam_role_policy" "csw_instance" {
  role   = aws_iam_role.csw_instance.id
  policy = data.aws_iam_policy_document.csw_instance.json
}

resource "aws_iam_instance_profile" "csw_instance" {
  name = "csw-instance-profile"
  role = aws_iam_role.csw_instance.name
}

# Render user_data
locals {
  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    agent_s3_uri        = var.csw_agent_s3_uri,
    ca_s3_uri           = var.csw_ca_s3_uri,
    ssm_param_name      = var.ssm_activation_key_name,
    csw_scope           = var.csw_scope,
  })
}

# Example: launch template suitable for an ASG
resource "aws_launch_template" "web" {
  name_prefix = "web-csw-"

  image_id      = data.aws_ami.al2023.id
  instance_type = "t3.medium"

  iam_instance_profile {
    arn = aws_iam_instance_profile.csw_instance.arn
  }

  metadata_options {
    http_tokens                 = "required"   # IMDSv2 only
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  user_data = base64encode(local.user_data)

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "web"
      csw_scope = var.csw_scope
    }
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

### `user-data.sh.tftpl`

```bash
#!/bin/bash
set -euxo pipefail

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)

# Pull payload
aws s3 cp "${agent_s3_uri}" /tmp/tet-sensor.rpm --region "$REGION"

mkdir -p /etc/tetration && chmod 750 /etc/tetration
aws s3 cp "${ca_s3_uri}" /etc/tetration/ca.pem --region "$REGION" --quiet || true

# Activation key from SSM
ACTIVATION_KEY=$(aws ssm get-parameter \
  --name "${ssm_param_name}" --with-decryption \
  --region "$REGION" --query Parameter.Value --output text)

cat > /etc/tetration/sensor.conf <<EOF
ACTIVATION_KEY=$ACTIVATION_KEY
SCOPE=${csw_scope}
EOF
chmod 640 /etc/tetration/sensor.conf

dnf install -y /tmp/tet-sensor.rpm
systemctl enable --now tetd
```

---

## Azure — minimal Terraform example

```hcl
terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
  }
}

variable "csw_scope"        { type = string }
variable "csw_blob_url_pkg" { type = string }   # https://...blob.core.windows.net/agents/...
variable "csw_blob_url_ca"  { type = string }
variable "csw_kv_name"      { type = string }
variable "csw_kv_secret"    { type = string }   # secret name in Key Vault holding activation key

resource "azurerm_user_assigned_identity" "csw_vm" {
  name                = "csw-vm-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
}

# Grant identity Storage Blob Data Reader on the agents container,
# and Key Vault Secrets User on the relevant secret. (RBAC examples
# omitted for brevity; see ./examples/terraform/azure-customdata.tf
# for the full set.)

locals {
  custom_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    blob_url_pkg = var.csw_blob_url_pkg,
    blob_url_ca  = var.csw_blob_url_ca,
    kv_name      = var.csw_kv_name,
    kv_secret    = var.csw_kv_secret,
    csw_scope    = var.csw_scope,
  })
}

resource "azurerm_linux_virtual_machine" "web" {
  name                  = "web-01"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = "Standard_D2s_v5"
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.web.id]

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.csw_vm.id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "9-lvm-gen2"
    version   = "latest"
  }

  custom_data = base64encode(local.custom_data)

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_ed25519.pub")
  }
}
```

The `cloud-init.yaml.tftpl` is the cloud-init YAML from
[`02-azure-customdata.md`](./02-azure-customdata.md), with
`${...}` Terraform interpolations.

---

## GCP — minimal Terraform example

```hcl
terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

variable "csw_scope"           { type = string }
variable "csw_gcs_pkg_url"     { type = string }   # https://storage.googleapis.com/...
variable "csw_gcs_ca_url"      { type = string }
variable "csw_secret_name"     { type = string }   # full secret resource name

resource "google_service_account" "csw_vm" {
  account_id   = "csw-vm-sa"
  display_name = "CSW VM service account"
}

resource "google_storage_bucket_iam_member" "csw_pkg_read" {
  bucket = "internal-csw-agents"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.csw_vm.email}"
}

resource "google_secret_manager_secret_iam_member" "csw_secret_read" {
  secret_id = var.csw_secret_name
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.csw_vm.email}"
}

locals {
  startup_script = templatefile("${path.module}/startup.sh.tftpl", {
    pkg_url     = var.csw_gcs_pkg_url,
    ca_url      = var.csw_gcs_ca_url,
    secret_name = var.csw_secret_name,
    csw_scope   = var.csw_scope,
  })
}

resource "google_compute_instance" "web" {
  name         = "web-01"
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "rhel-cloud/rhel-9"
    }
  }

  network_interface {
    network    = "default"
    subnetwork = "default"
    access_config { }
  }

  service_account {
    email  = google_service_account.csw_vm.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    "startup-script" = local.startup_script
    "csw_scope"      = var.csw_scope
  }
}
```

---

## Activation key handling across clouds

| Cloud | Recommended secret store | Identity |
|---|---|---|
| AWS | SSM Parameter Store (SecureString) or Secrets Manager | EC2 instance role |
| Azure | Key Vault (secret) | User-assigned managed identity attached to the VM |
| GCP | Secret Manager | Service account attached to the VM |

In all three, **the secret never appears in the Terraform code**.
Terraform references the secret name; the VM identity reads the
secret at runtime. The Terraform plan and any state file capture
contain only the secret's *path*, not its value.

---

## Wave-based rollout in Terraform

The standard pattern is workspaces or per-environment state:

| Wave | Workspace |
|---|---|
| Lab | `terraform workspace select lab; terraform apply` |
| Stage | `terraform workspace select stage; terraform apply` |
| Prod canary | `terraform workspace select prod-canary` |
| Prod | `terraform workspace select prod` |

Each workspace has its own state, its own variable file, and its
own scope (`csw_scope = "prod-canary:web-tier"` vs `csw_scope =
"prod:web-tier"`). Replacing instances is a `terraform apply` in
each workspace in sequence.

For ASG / VMSS / MIG resources, use the cloud's native rolling-
update settings to control concurrency:

- AWS ASG: `instance_refresh { strategy = "Rolling"; preferences {
  min_healthy_percentage = 90 } }`
- Azure VMSS: `upgrade_mode = "Rolling"` with rolling policy
- GCP MIG: `update_policy { type = "PROACTIVE"; max_surge_fixed = 3 }`

---

## Day-2 patching cadence in Terraform

When CSW publishes a new agent release:

1. Upload the new package to S3 / Blob / GCS with a versioned key
2. Bump a `csw_agent_version` Terraform variable (referenced in
   the user_data / custom_data / startup-script template)
3. `terraform plan` shows the user-data change → instances will be
   replaced
4. Apply per-environment in waves

For Golden AMI / Compute Gallery / GCE custom images, the same
pattern applies but the variable is the image ID instead of the
package version.

---

## See also

- [`./examples/terraform/`](./examples/terraform/) — runnable Terraform per cloud
- [`01-aws-userdata.md`](./01-aws-userdata.md), [`02-azure-customdata.md`](./02-azure-customdata.md), [`03-gcp-startup-script.md`](./03-gcp-startup-script.md)
- [`05-golden-ami.md`](./05-golden-ami.md), [`06-azure-vm-image.md`](./06-azure-vm-image.md)
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md)
