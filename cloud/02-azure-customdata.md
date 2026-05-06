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
  --file tet-sensor-3.x.y.z-1.el9.x86_64.rpm \
  --name linux/el9/tet-sensor-3.x.y.z-1.el9.x86_64.rpm \
  --auth-mode login

az storage blob upload \
  --account-name internalcswagents \
  --container-name agents \
  --file ca.pem \
  --name linux/ca.pem \
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

      # Pull the agent package
      curl -s -L -H "Authorization: Bearer $TOKEN" -H "x-ms-version: 2019-12-12" \
        -o /tmp/tet-sensor.rpm \
        "https://internalcswagents.blob.core.windows.net/agents/linux/el9/tet-sensor-3.x.y.z-1.el9.x86_64.rpm"

      # Pull the CA
      mkdir -p /etc/tetration && chmod 750 /etc/tetration
      curl -s -L -H "Authorization: Bearer $TOKEN" -H "x-ms-version: 2019-12-12" \
        -o /etc/tetration/ca.pem \
        "https://internalcswagents.blob.core.windows.net/agents/linux/ca.pem"

      # Get activation key from Key Vault (use az login with managed identity)
      az login --identity --output none
      ACTIVATION_KEY=$(az keyvault secret show \
        --vault-name csw-prod-kv \
        --name activation-key-prod-web \
        --query value -o tsv)

      cat > /etc/tetration/sensor.conf <<EOF
      ACTIVATION_KEY=$ACTIVATION_KEY
      SCOPE=prod:web-tier
      EOF
      chmod 640 /etc/tetration/sensor.conf

      # Install
      dnf install -y /tmp/tet-sensor.rpm

      # Start
      systemctl enable --now csw-agent
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
$msiUrl = "https://internalcswagents.blob.core.windows.net/agents/windows/TetrationAgentInstaller-3.x.y.z-x64.msi"
Invoke-WebRequest -Uri $msiUrl -Headers $h -OutFile C:\Windows\Temp\TetSensor.msi

# Pull CA (on-prem clusters)
$caUrl = "https://internalcswagents.blob.core.windows.net/agents/windows/ca.pem"
$tetConf = "$env:ProgramData\Cisco\Tetration\conf"
New-Item -ItemType Directory -Force -Path $tetConf | Out-Null
Invoke-WebRequest -Uri $caUrl -Headers $h -OutFile "$tetConf\ca.pem"

# Get activation key from Key Vault
$kvTokenResp = Invoke-RestMethod -Headers @{Metadata="true"} -Method GET `
  -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net"
$kvToken = $kvTokenResp.access_token
$secret = Invoke-RestMethod -Headers @{Authorization="Bearer $kvToken"} -Method GET `
  -Uri "https://csw-prod-kv.vault.azure.net/secrets/activation-key-prod-web?api-version=7.4"

# (Activation key is read into $secret.value; the CSW MSI bakes the key in
# during the CSW UI generation step. If you regenerate from the UI, you may
# not need to re-set it here. Otherwise write it to the agent registry per
# your CSW release's documented method.)

# Install
$args = @(
  "/i", '"C:\Windows\Temp\TetSensor.msi"',
  "/quiet", "/norestart",
  "/L*v", "C:\Windows\Temp\tetsensor-install.log"
)
Start-Process -FilePath msiexec.exe -ArgumentList $args -Wait

# Verify
Start-Sleep -Seconds 30
$svc = Get-Service -Name CswAgent -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne 'Running') {
  Start-Service -Name CswAgent -ErrorAction Continue
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

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `cloud-init` runs but agent install fails at storage pull | Managed identity not yet available; ran too early | Add `sleep 30` before the first metadata call (the example above already does this) |
| Storage pull returns 403 | Managed identity missing Storage Blob Data Reader on the container | Re-run `az role assignment create`; new role assignments take 5+ minutes to propagate |
| Key Vault access denied | Managed identity missing `get` on Key Vault secrets | Either RBAC (`az role assignment create --role 'Key Vault Secrets User' ...`) or access policy (`az keyvault set-policy --vault-name <kv> --object-id <id> --secret-permissions get`) |
| `custom_data` shows up unparsed (literal cloud-init YAML) on Linux | base64 encoding mismatch | Confirm the value passed to Azure is base64; Terraform's `base64encode(...)` is your friend |
| Windows `<powershell>` block doesn't run | `custom_data` not configured to execute | Use the [Custom Script Extension](https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows) for Windows; or use Azure Image Builder to bake the agent in |

Full troubleshooting in
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## See also

- [`./examples/terraform/azure-customdata.tf`](./examples/terraform/azure-customdata.tf) — runnable Terraform
- [`./examples/cloud-init/azure-csw-rhel9.yaml`](./examples/cloud-init/azure-csw-rhel9.yaml) — runnable cloud-init
- [`04-terraform.md`](./04-terraform.md) — multi-cloud IaC patterns
- [`06-azure-vm-image.md`](./06-azure-vm-image.md) — image-baked alternative
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md)
