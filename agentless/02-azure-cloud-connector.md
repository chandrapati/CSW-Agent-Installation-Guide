# Agentless — Azure Cloud Connector

CSW pulls inventory and (optionally) NSG Flow Logs from each
Azure subscription it's connected to. Authentication is via a
**service principal** with read access at the subscription
scope; no agent runs on Azure VMs.

---

## What you get

- Continuous VM / VMSS / AKS / Storage / SQL / Load Balancer
  inventory across the connected subscriptions
- Tags and metadata enrichment (region, resource group, NIC,
  NSG, attached managed identity)
- NSG Flow Log ingest (when the destination Storage account is
  reachable)
- Reconciliation against the host-agent inventory: CSW shows
  which VMs have an agent and which don't

## What you don't get

- Same as the AWS connector — no process, software, CVE, or
  enforcement. Use the agent for those.

---

## Prerequisites

- Azure subscription(s) you want to connect
- Permission to create a service principal (or to consent to a
  CSW-published Enterprise Application) and grant it
  subscription-scope RBAC
- For NSG Flow Logs: an existing flow-logs Storage account, OR
  rights to enable Network Watcher + create the Storage account

---

## Step 1 — Create a service principal

```bash
# Via az CLI — most teams' default
SUB_ID=$(az account show --query id -o tsv)

az ad sp create-for-rbac \
  --name "csw-cloud-connector-${SUB_ID}" \
  --role "Reader" \
  --scopes "/subscriptions/${SUB_ID}" \
  --years 2

# Output includes:
#   "appId":       "<APPLICATION-ID>"
#   "tenant":      "<TENANT-ID>"
#   "password":    "<CLIENT-SECRET>"   <-- treat as a secret
```

Capture `appId`, `tenant`, and `password` — paste into the CSW
UI in Step 3.

> Prefer a **certificate-based** service principal in regulated
> environments — `az ad sp create-for-rbac --create-cert` —
> instead of a client secret. The trade-off is that you'll need
> to upload the certificate to CSW (or use the connector's
> federated-identity option in releases that support it).

---

## Step 2 — Grant flow-log read (if you want flow telemetry)

NSG Flow Logs land in a Storage account blob container. The
service principal needs read access:

```bash
# The Storage account / container holding NSG flow logs
STORAGE_ACCT="nsgflowlogs<env>"
RG_ID=$(az group show -n <storage-rg> --query id -o tsv)

# Grant Storage Blob Data Reader on the container
az role assignment create \
  --assignee <APPLICATION-ID> \
  --role "Storage Blob Data Reader" \
  --scope "${RG_ID}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCT}/blobServices/default/containers/insights-logs-networksecuritygroupflowevent"
```

If NSG Flow Logs are not yet enabled on your VNets:

```bash
# Enable Network Watcher in the region (one-time per region)
az network watcher configure --resource-group NetworkWatcherRG \
  --locations <region> --enabled true

# Enable flow logs on each NSG
az network watcher flow-log create \
  --resource-group <nsg-rg> \
  --name <flow-log-name> \
  --nsg <nsg-name> \
  --storage-account <storage-acct-id> \
  --enabled true \
  --retention 30 \
  --format JSON --log-version 2 \
  --traffic-analytics true \
  --workspace <log-analytics-workspace-id>
```

> **Cost note.** NSG Flow Logs in production VNets can be
> expensive. Set sensible retention; consider sampling at the
> Traffic Analytics layer.

---

## Step 3 — Configure the connector in the CSW UI

1. Log into the CSW UI
2. Navigate to *Manage → External Orchestrators → Azure*
3. Click *Add Connector*
4. Provide:
   - Connector name (e.g., `azure-prod-sub-XXXX`)
   - Tenant ID
   - Subscription ID
   - Service Principal Application ID
   - Service Principal Secret (or certificate)
   - NSG Flow Log Storage Account (if Step 2 done)
5. Click *Test Connection*. CSW authenticates as the SP and
   validates `Microsoft.Compute/*/read` and related permissions.
6. Save. First inventory sync runs within an hour.

---

## Step 4 — Verify

- *Organize → Inventory → Filter by `cloud_subscription = <sub-id>`*
  — every VM the SP can `Microsoft.Compute/virtualMachines/read`
  should appear
- *Investigate → Flows → Filter by source/dest in the VNet* —
  flow records appear within 10–15 minutes
- *Manage → External Orchestrators → click the connector* — last
  successful sync timestamp should be recent

---

## Multi-subscription at scale (Management Groups)

For many subscriptions, don't grant Reader per-subscription by
hand:

- Create the service principal once in the tenant
- Assign Reader at the **Management Group** scope that contains
  all in-scope subscriptions
- For NSG Flow Log read, use a Management Group–scoped custom
  role that grants `Microsoft.Storage/.../read` on flow-log
  containers across the org

In CSW, add each subscription as its own connector (one
connector record per subscription is current best practice).

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| "Test Connection" fails with `AADSTS7000215` | Client secret expired / wrong | Generate a new secret; update CSW |
| Inventory sync OK but no flow logs | Service principal missing Storage Blob Data Reader | Re-run the role assignment in Step 2; assignments take 5+ min to propagate |
| Connector misses VMs in a specific RG | RG-scoped SP grant rather than subscription-scoped | Re-create the SP role assignment at subscription scope |
| Connector flagged as a "guest application" by Conditional Access | Default Conditional Access for service principals can block API access | Add a Named Location / SP exception specific to the CSW connector |
| Cost spike from NSG Flow Logs and Traffic Analytics | Default settings on production VNets | Reduce sampling or move to Storage-only delivery (no Traffic Analytics) |

---

## See also

- [`05-comparison-matrix.md`](./05-comparison-matrix.md)
- [`../cloud/02-azure-customdata.md`](../cloud/02-azure-customdata.md) — agent path for Azure VMs
- [`../cloud/06-azure-vm-image.md`](../cloud/06-azure-vm-image.md)
