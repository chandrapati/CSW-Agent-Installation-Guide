# Example Packer template — bake CSW agent into an Azure Compute Gallery image.
#
# Pattern X (deferred activation): the agent package is installed and `csw-agent`
# is masked at build time; activation happens at first boot via a one-shot
# systemd unit that pulls the activation key from Key Vault using the
# instance's managed identity.

packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 2.1"
    }
  }
}

variable "subscription_id" { type = string }
variable "tenant_id"       { type = string }
variable "client_id"       { type = string }
variable "client_secret"   { type = string sensitive = true }
variable "location"        { type = string default = "eastus" }
variable "csw_pkg_url"     { type = string description = "Azure Blob URL for tet-sensor.rpm" }
variable "csw_ca_url"      { type = string description = "Azure Blob URL for ca.pem" }

source "azure-arm" "rhel9_csw" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret

  os_type         = "Linux"
  image_publisher = "RedHat"
  image_offer     = "RHEL"
  image_sku       = "9-lvm-gen2"

  managed_image_name                = "rhel9-csw-${formatdate("YYYY-MM-DD", timestamp())}"
  managed_image_resource_group_name = "csw-images-rg"
  location                          = var.location
  vm_size                           = "Standard_D2s_v5"

  shared_image_gallery_destination {
    subscription          = var.subscription_id
    resource_group        = "csw-images-rg"
    gallery_name          = "csw_images"
    image_name            = "rhel9-csw"
    image_version         = formatdate("YYYY.MM.DD", timestamp())
    replication_regions   = [var.location]
    storage_account_type  = "Premium_LRS"
  }
}

build {
  sources = ["source.azure-arm.rhel9_csw"]

  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "sudo dnf -y update",
      "sudo dnf -y install jq curl ca-certificates",
    ]
  }

  provisioner "shell" {
    inline = [
      "set -euo pipefail",
      "curl -fsSL '${var.csw_pkg_url}' -o /tmp/tet-sensor.rpm",
      "curl -fsSL '${var.csw_ca_url}'  -o /tmp/ca.pem",
      "sudo install -m 0644 /tmp/ca.pem /etc/tetration/ca.pem",
      "sudo dnf -y install /tmp/tet-sensor.rpm",
      "sudo systemctl mask csw-agent  # deferred — activated at first boot",
      "sudo rm -f /tmp/tet-sensor.rpm /tmp/ca.pem",
    ]
  }

  provisioner "file" {
    source      = "../cloud-init/csw-first-boot-azure.sh"
    destination = "/tmp/csw-first-boot.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo install -m 0755 /tmp/csw-first-boot.sh /usr/local/bin/csw-first-boot.sh",
      "sudo tee /etc/systemd/system/csw-first-boot.service >/dev/null <<'EOF'",
      "[Unit]",
      "Description=CSW agent first-boot activation",
      "After=cloud-init.service network-online.target",
      "Wants=network-online.target",
      "ConditionPathExists=!/var/lib/csw/activated",
      "",
      "[Service]",
      "Type=oneshot",
      "ExecStart=/usr/local/bin/csw-first-boot.sh",
      "RemainAfterExit=yes",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "sudo systemctl enable csw-first-boot.service",
    ]
  }

  provisioner "shell" {
    inline = [
      "test -x /usr/local/bin/csw-first-boot.sh",
      "test -f /etc/systemd/system/csw-first-boot.service",
      "rpm -q tet-sensor",
      "echo 'Sanity checks passed.'",
    ]
  }
}
