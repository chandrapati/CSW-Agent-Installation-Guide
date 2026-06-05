# Azure — Install via VM `custom_data` / `cloud-init`

Azure equivalent of the AWS `user_data` pattern. The `custom_data`
field of an `azurerm_linux_virtual_machine` (or VM Scale Set) is
passed to `cloud-init` at first boot. For Windows, `custom_data`
is also available but the install is wrapped in a PowerShell
script.

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- An Azure VM (Linux or Windows) with `cloud-init` (Linux) or
  `Windows Setup` (Windows) reading the `custom_data` field
- Outbound 443 from the VM to the CSW cluster (default Azure
  egress allows this; an NSG or Azure Firewall may block it)
- The CSW agent payload reachable somewhere — three patterns:
  - **Pattern A (recommended)**: a private Azure Storage Blob
    container with the agent payload and CA chain
  - **Pattern B**: workload reaches the cluster directly and
    runs the CSW-generated installer script
  - **Pattern C**: pre-baked Azure Compute Gallery image
    ([06-azure-vm-image.md](./06-azure-vm-image.md))

---

## Pattern A — payload from a private Storage Blob container

### One-time setup

```bash
# Stage the package and CA in private blob storage
az storage container create \
  --account-name internalcswagents \
  --name agents \
  --auth-mode login \
  --public-access off

az storage blob upload \
  --account-name internalcswagents \
  --container-name agents \
  --file tetration_linux_installer.sh \
  --name linux/tetration_linux_installer.sh \
  --auth-mode login

# Grant the VM's managed identity Storage Blob Data Reader on the container
RG_ID=$(az group show -n my-rg --query id -o tsv)
SCOPE="$RG_ID/providers/Microsoft.Storage/storageAccounts/internalcswagents/blobServices/default/containers/agents"

az role assignment create \
  --assignee <managed-identity-principal-id> \
  --role "Storage Blob Data Reader" \
  --scope "$SCOPE"
```

### `custom_data` cloud-init script (Linux — RHEL family)

The Linux `custom_data` field on `azurerm_linux_virtual_machine`
must be **base64-encoded** before sending to Azure. Terraform
handles this with `base64encode(...)`. The script content itself
is plain `cloud-init` user-data:

```yaml
#cloud-config
write_files:
  - path: /usr/local/sbin/install-csw.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -euxo pipefail

      # Wait for system identity (managed identity) to be available
      sleep 30

      # Get an OAuth token for the managed identity to access Storage
      TOKEN=$(curl -s -H "Metadata: true" \
        "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

      # Pull the CSW-generated installer script. Treat this script
      # as a secret because it embeds activation material.
      curl -s -L -H "Authorization: Bearer $TOKEN" -H "x-ms-version: 2019-12-12" \
        -o /tmp/tetration_linux_installer.sh \
        "https://internalcswagents.blob.core.windows.net/agents/linux/tetration_linux_installer.sh"

      # Install
      chmod 700 /tmp/tetration_linux_installer.sh
      bash /tmp/tetration_linux_installer.sh
runcmd:
  - /usr/local/sbin/install-csw.sh
```

### Why this pattern

- **Managed Identity** removes the need for any secret in the
  `custom_data` (which is visible in the VM's `osProfile`).
- **Key Vault** holds the activation key; only the VM's identity
  can fetch it.
- **Versioned blob keys** make upgrades a path change.
- **Private endpoint** on the storage account keeps payload pulls
  off the public Internet.

### Windows variant

For Windows, `custom_data` is decoded into `C:\AzureData\CustomData.bin`
on first boot. You wrap the install in PowerShell that reads the
file:

```powershell
# Provide via custom_data (base64-encoded by Terraform):
<powershell>
$ErrorActionPreference = 'Stop'

# Get a managed-identity token
$tokenResp = Invoke-RestMethod -Headers @{Metadata="true"} -Method GET `
  -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/"

$token = $tokenResp.access_token
$h = @{ Authorization = "Bearer $token"; "x-ms-version" = "2019-12-12" }

# Pull MSI
# NOTE: replace the filename below with the exact installer name from
# your CSW UI or extracted Agent Image Installer package.
$msiFilename = "TetrationAgentInstaller-3.x.y.z-x64.msi"
$msiUrl = "https://internalcswagents.blob.core.windows.net/agents/windows/$msiFilename"
$msiLocal = "C:\Windows\Temp\$msiFilename"
Invoke-WebRequest -Uri $msiUrl -Headers $h -OutFile $msiLocal

# Install
$args = @(
  "/i", "`"$msiLocal`"",
  "/quiet", "/norestart",
  "/L*v", "C:\Windows\Temp\csw-agent-install.log"
)
Start-Process -FilePath msiexec.exe -ArgumentList $args -Wait

# Verify
Start-Sleep -Seconds 30
$svc = Get-Service -Name CswAgent -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne 'Running') {
  if ($svc) { Start-Service -Name $svc.Name -ErrorAction Continue }
}
</powershell>
```

The `<powershell>...</powershell>` wrapper tells Azure VM
extension `WindowsCustomScript` (or the OS itself, depending on
how `custom_data` is configured) to run the contents at first
boot.

---

## Pattern B — CSW-generated installer (no blob prep)

If the workload has direct egress to the CSW cluster, ship the
CSW-generated installer in `custom_data` directly. Same trade-offs
as the AWS Pattern B: lower prep cost, less version control.

---

## Pattern C — payload baked into a Compute Gallery image

The recommended pattern at scale. See
[06-azure-vm-image.md](./06-azure-vm-image.md).

---

## Wave-based rollout

In Terraform / Azure CLI / Bicep estates, wave-based rollout
typically means:

| Wave | Mechanism |
|---|---|
| Lab | Apply in lab subscription / resource group; replace a few VMs |
| Stage | Apply in stage subscription |
| Prod canary | Apply with `count = 1` for a canary VM Scale Set |
| Prod rest | Apply across remaining scale sets, with VMSS upgrade policy `Rolling` and a small `max_batch_size` |

For VM Scale Sets:

```hcl
resource "azurerm_linux_virtual_machine_scale_set" "web" {
  # ...
  upgrade_mode = "Rolling"
  rolling_upgrade_policy {
    max_batch_instance_percent              = 10
    max_unhealthy_instance_percent          = 20
    max_unhealthy_upgraded_instance_percent = 5
    pause_time_between_batches              = "PT5M"
  }
  health_probe_id = azurerm_lb_probe.csw_ready.id   # custom probe that asserts the agent is registered
}
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `cloud-init` runs but install fails at storage pull | Managed identity not ready | Add delay before first metadata call (example already includes `sleep 30`) |
| Storage pull returns 403 | MI missing Storage Blob Data Reader | Re-run role assignment; allow 5+ min propagation |
| Key Vault access denied | MI missing secret get permission | Assign Key Vault Secrets User or access policy |
| `custom_data` unparsed on Linux | base64 encoding mismatch | Use Terraform `base64encode(...)` |
| Windows block doesn't run | `custom_data` not executed on Windows | Use Custom Script Extension or bake into image |
| Agent *Not Active* | `user.cfg` not created before install in cloud-init | Add cloud-init write_files for `user.cfg` before install command |

Full troubleshooting: [`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md)

---

## See also

- Terraform example intentionally removed until it can be rebuilt
  around the CSW-generated installer-script flow.
- [`./examples/cloud-init/azure-csw-rhel9.yaml`](./examples/cloud-init/azure-csw-rhel9.yaml) — runnable cloud-init
- [`04-terraform.md`](./04-terraform.md) — multi-cloud IaC patterns
- [`06-azure-vm-image.md`](./06-azure-vm-image.md) — image-baked alternative
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md)
