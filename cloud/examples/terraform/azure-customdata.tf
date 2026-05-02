# Example Terraform — Azure VM Scale Set with CSW agent installed via custom_data.
#
# Pattern: a per-cluster cloud-init payload reads the agent package from a
# Storage Blob and the activation key from Key Vault using the VM's
# system-assigned managed identity.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location"            { type = string }
variable "resource_group_name" { type = string }
variable "vnet_subnet_id"      { type = string }
variable "csw_pkg_blob_url"    { type = string }
variable "csw_keyvault_uri"    { type = string }
variable "csw_keyvault_secret" { type = string default = "csw-activation-key" }

resource "azurerm_user_assigned_identity" "csw" {
  name                = "csw-vm-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_role_assignment" "csw_kv_reader" {
  scope                = var.csw_keyvault_uri
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.csw.principal_id
}

resource "azurerm_role_assignment" "csw_blob_reader" {
  scope                = azurerm_storage_account.csw_pkg.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.csw.principal_id
}

# Reference: storage account where you've placed the agent package and CA chain
data "azurerm_storage_account" "csw_pkg" {
  name                = "cswpkgstorage"
  resource_group_name = var.resource_group_name
}

resource "azurerm_linux_virtual_machine_scale_set" "app" {
  name                = "app-vmss"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard_D2s_v5"
  instances           = 3
  admin_username      = "azureuser"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.csw.id]
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "9-lvm-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "primary"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = var.vnet_subnet_id
    }
  }

  custom_data = base64encode(templatefile("${path.module}/../cloud-init/azure-csw-rhel9.yaml", {
    csw_pkg_blob_url      = var.csw_pkg_blob_url
    csw_ca_blob_url       = replace(var.csw_pkg_blob_url, "/tet-sensor.rpm", "/ca.pem")
    csw_keyvault_uri      = var.csw_keyvault_uri
    csw_keyvault_secret   = var.csw_keyvault_secret
    csw_cluster_endpoint  = "csw.example.com"
  }))

  upgrade_mode = "Rolling"

  rolling_upgrade_policy {
    max_batch_instance_percent              = 20
    max_unhealthy_instance_percent          = 25
    max_unhealthy_upgraded_instance_percent = 10
    pause_time_between_batches              = "PT5M"
  }
}
