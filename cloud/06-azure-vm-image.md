# Azure — Compute Gallery Image

The Azure analogue of the AWS Golden AMI. Bake the CSW agent
into a Compute Gallery image (formerly *Shared Image Gallery*)
during the build phase. Every new VM (or VMSS instance) launched
from this image has the agent pre-installed.

> Read [`05-golden-ami.md`](./05-golden-ami.md) first — the
> conceptual decisions (Pattern X vs. Pattern Y, image lifecycle,
> when to bake vs. first-boot) are identical. This doc covers the
> Azure-specific build mechanics.

---

## Build options on Azure

Three build options, in increasing order of automation:

1. **Manual capture from a customised VM**
   - Spin up a VM, install the agent interactively, run
     `sysprep` (Windows) or `waagent -deprovision` (Linux),
     capture as a Managed Image, publish to Compute Gallery
   - Suitable for one-off / lab images; hard to automate
2. **Packer with the `azure-arm` builder**
   - Packer builds the VM, runs your provisioners, captures the
     image, and uploads to Compute Gallery
   - Same template language as AWS Golden AMI; recommended for
     orgs with an existing Packer practice
3. **Azure Image Builder (managed Packer)**
   - Azure-native managed service; same Packer engine under the
     hood, run as an Azure resource
   - Recommended for orgs that prefer Azure-native tooling and
     want the build process integrated with Azure RBAC, KMS,
     and policy

The Packer template below is option 2.

---

## Step 1 — Choose the activation pattern

Same decision as AWS Golden AMI:

- **Pattern X** — bake binaries; defer activation to first boot
  via `custom_data` / cloud-init / Custom Script Extension.
  Recommended default.
- **Pattern Y** — activate during image build; the image carries
  the activation key in `sensor.conf`. Tighter image distribution
  controls required.

Pattern X shown below.

---

## Step 2 — Author the Packer template

### `compute-gallery-csw.pkr.hcl`

```hcl
packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 2.0"
    }
  }
}

variable "subscription_id"           {}
variable "client_id"                 {}                   # service principal for Packer
variable "client_secret"             { sensitive = true }
variable "tenant_id"                 {}

variable "build_resource_group"      { default = "rg-packer-csw" }
variable "image_resource_group"      { default = "rg-images" }
variable "compute_gallery_name"      { default = "internalImages" }
variable "image_definition_name"     { default = "rhel9-csw" }
variable "image_version"             { default = "1.0.0" }
variable "csw_agent_blob_url"        {}                   # https://...blob.core.windows.net/agents/...
variable "csw_ca_blob_url"           {}
variable "location"                  { default = "eastus" }

source "azure-arm" "rhel9_csw" {
  subscription_id  = var.subscription_id
  client_id        = var.client_id
  client_secret    = var.client_secret
  tenant_id        = var.tenant_id

  os_type          = "Linux"
  image_publisher  = "RedHat"
  image_offer      = "RHEL"
  image_sku        = "9-lvm-gen2"
  vm_size          = "Standard_D2s_v5"
  location         = var.location
  build_resource_group_name = var.build_resource_group

  # Publish to Compute Gallery
  shared_image_gallery_destination {
    subscription      = var.subscription_id
    resource_group    = var.image_resource_group
    gallery_name      = var.compute_gallery_name
    image_name        = var.image_definition_name
    image_version     = var.image_version
    replication_regions = [var.location]
  }

  # Tags
  azure_tags = {
    csw_agent_baked = "true"
    base_lineage    = "RHEL/9-lvm-gen2"
  }
}

build {
  sources = ["source.azure-arm.rhel9_csw"]

  # Patch baseline
  provisioner "shell" {
    inline = [
      "sudo dnf upgrade -y",
      "sudo dnf install -y kernel-headers-$(uname -r) || true",
    ]
  }

  # Install the CSW agent (Pattern X — defer activation)
  provisioner "shell" {
    inline = [
      "set -euxo pipefail",
      "sudo mkdir -p /etc/tetration && sudo chmod 750 /etc/tetration",

      # Pull the agent payload via curl with managed-identity token
      "TOKEN=$(curl -s -H 'Metadata: true' 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/' | python3 -c 'import sys,json;print(json.load(sys.stdin)[\"access_token\"])')",

      "sudo curl -s -L -H \"Authorization: Bearer $TOKEN\" -H \"x-ms-version: 2019-12-12\" -o /tmp/tet-sensor.rpm '${var.csw_agent_blob_url}'",

      "sudo curl -s -L -H \"Authorization: Bearer $TOKEN\" -H \"x-ms-version: 2019-12-12\" -o /etc/tetration/ca.pem '${var.csw_ca_blob_url}'",

      "sudo dnf install -y /tmp/tet-sensor.rpm",
      "sudo rm -f /tmp/tet-sensor.rpm",

      "sudo systemctl disable tetd",
      "sudo systemctl mask tetd",
    ]
  }

  # Drop the first-boot oneshot service
  provisioner "file" {
    source      = "files/csw-first-boot.sh"
    destination = "/tmp/csw-first-boot.sh"
  }
  provisioner "shell" {
    inline = [
      "sudo install -m 0755 /tmp/csw-first-boot.sh /usr/local/sbin/csw-first-boot.sh",
      "sudo bash -c 'cat > /etc/systemd/system/csw-first-boot.service' <<'UNIT'",
      "[Unit]",
      "Description=Cisco Secure Workload first-boot activation",
      "After=cloud-init-local.service network-online.target",
      "Wants=network-online.target",
      "ConditionPathExists=!/var/lib/csw-activated",
      "",
      "[Service]",
      "Type=oneshot",
      "ExecStart=/usr/local/sbin/csw-first-boot.sh",
      "RemainAfterExit=yes",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "UNIT",
      "sudo systemctl enable csw-first-boot.service",
    ]
  }

  # Sysprep / deprovision (Linux: waagent -deprovision)
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline = [
      "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"
    ]
  }
}
```

### `files/csw-first-boot.sh`

Same shape as the AWS first-boot script, but uses Azure
metadata + Key Vault:

```bash
#!/bin/bash
set -euxo pipefail
exec > /var/log/csw-first-boot.log 2>&1

# Wait for managed identity to be ready
sleep 30

# Get a Key Vault token via the VM's managed identity
TOKEN=$(curl -s -H 'Metadata: true' \
  'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

# Convention: VM tag csw_kv_secret holds the secret URL
KV_SECRET_URL=$(curl -s -H 'Metadata: true' \
  'http://169.254.169.254/metadata/instance/compute/tagsList?api-version=2021-12-13' \
  | python3 -c 'import sys,json; tags={t["name"]:t["value"] for t in json.load(sys.stdin)}; print(tags.get("csw_kv_secret",""))')

CSW_SCOPE=$(curl -s -H 'Metadata: true' \
  'http://169.254.169.254/metadata/instance/compute/tagsList?api-version=2021-12-13' \
  | python3 -c 'import sys,json; tags={t["name"]:t["value"] for t in json.load(sys.stdin)}; print(tags.get("csw_scope","default"))')

ACTIVATION_KEY=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "${KV_SECRET_URL}?api-version=7.4" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')

cat > /etc/tetration/sensor.conf <<EOF
ACTIVATION_KEY=$ACTIVATION_KEY
SCOPE=$CSW_SCOPE
EOF
chmod 640 /etc/tetration/sensor.conf

systemctl unmask tetd
systemctl enable --now tetd

touch /var/lib/csw-activated
```

---

## Step 3 — Build the image

```bash
packer init compute-gallery-csw.pkr.hcl
packer fmt -recursive .

packer build \
  -var "subscription_id=$AZ_SUB" \
  -var "client_id=$AZ_CLIENT" \
  -var "client_secret=$AZ_SECRET" \
  -var "tenant_id=$AZ_TENANT" \
  -var "image_version=1.0.0" \
  -var "csw_agent_blob_url=https://internalcswagents.blob.core.windows.net/agents/linux/el9/tet-sensor-3.10.1.45-1.el9.x86_64.rpm" \
  -var "csw_ca_blob_url=https://internalcswagents.blob.core.windows.net/agents/linux/ca.pem" \
  compute-gallery-csw.pkr.hcl
```

The output is a new image version in your Compute Gallery's
*image definition*.

---

## Step 4 — Reference the image in Terraform

```hcl
data "azurerm_shared_image_version" "rhel9_csw_latest" {
  name                = "latest"
  image_name          = "rhel9-csw"
  gallery_name        = "internalImages"
  resource_group_name = "rg-images"
}

resource "azurerm_linux_virtual_machine" "web" {
  name                = "web-01"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = "Standard_D2s_v5"
  admin_username      = "azureuser"
  network_interface_ids = [azurerm_network_interface.web.id]

  source_image_id = data.azurerm_shared_image_version.rhel9_csw_latest.id

  # The first-boot script reads the Key Vault URL from these tags
  tags = {
    csw_scope      = "prod:web-tier"
    csw_kv_secret  = "https://csw-prod-kv.vault.azure.net/secrets/activation-key-prod-web"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.csw_vm.id]
  }

  # ... os_disk, admin_ssh_key etc.
}
```

The user-assigned managed identity must have *Key Vault Secrets
User* on the activation-key secret.

---

## Step 5 — Image lifecycle

| Cadence | Action |
|---|---|
| Monthly (or on CSW agent release) | Re-run Packer build with new agent version; publish a new `image_version` in the gallery |
| Quarterly | Re-baseline against latest hardened base image; update Packer template |
| Per security patch window | Patch baseline OS in the Packer build; publish |
| Always | Tag old image versions with deprecation date; delete after grace period |

In Compute Gallery, image *versions* (e.g., `1.0.0`, `1.0.1`)
under the same *image definition* (e.g., `rhel9-csw`) are how
you express progressive releases. VMs reference either a specific
version or `latest`.

---

## Pattern Y deltas (activate during build)

Same shape as the AWS variant: in the Packer build, `aws ssm
get-parameter` becomes `az keyvault secret show` (using the
Packer service principal's Key Vault access). The image carries
the activation key — treat as sensitive and restrict
distribution.

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Packer build fails to access blob storage | Builder VM has no managed identity / wrong RBAC | Use `azure-arm` builder's `os_disk_resource_group` and assign managed identity to the builder VM; or pre-place the package on the builder via SSH provisioner |
| Image version conflict ("VersionAlreadyExists") | Re-running with the same `image_version` | Use a CI variable that bumps `image_version` automatically (timestamp / build number) |
| First-boot script never runs | Image deprovision didn't fire `cloud-init` | Ensure `waagent -deprovision+user` was the last build step; otherwise the image still remembers the build VM's instance state |
| VM launched from image starts `tetd` immediately and registers as the *image build* host | `tetd` was not masked before deprovision | Mask `tetd` during the build (Pattern X above) |
| Compute Gallery distribution to other regions takes hours | Cross-region replication is asynchronous | Set `replication_regions` to all consumer regions in the Packer template |

---

## When this is the right method

- **Azure at scale** — every fleet beyond a few hundred VMs
  benefits
- **VM Scale Sets with frequent scale events**
- **Orgs with an existing Compute Gallery practice**
- **Regulated environments** that gate on an attested base image

## When this is NOT the right method

- **Lab / sandbox subscriptions** — first-boot install is fine
- **No image-build pipeline yet** — first-boot first; image pipeline next

---

## See also

- [`05-golden-ami.md`](./05-golden-ami.md) — AWS Golden AMI (conceptually identical)
- [`02-azure-customdata.md`](./02-azure-customdata.md) — first-boot alternative
- [`04-terraform.md`](./04-terraform.md) — Terraform that consumes the gallery image
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md) — image-rebuild as the upgrade vehicle
