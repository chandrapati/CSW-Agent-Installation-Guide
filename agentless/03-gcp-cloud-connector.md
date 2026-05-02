# Agentless — GCP Cloud Connector

CSW pulls inventory and (optionally) VPC Flow Logs from each
GCP organisation / project it's connected to. Authentication is
via a **service account** with read access at the project (or
folder / org) scope; no agent runs on Compute Engine instances.

---

## What you get

- Continuous Compute Engine / GKE / Cloud SQL / Cloud Storage /
  Load Balancer inventory across the connected projects
- Tags, labels, and metadata enrichment (region, zone, network,
  subnet, service account, attached disks)
- VPC Flow Log ingest (when the destination Cloud Logging sink
  is reachable)
- Reconciliation against the host-agent inventory

## What you don't get

- Same as AWS / Azure — no process, software, CVE, or
  enforcement. Use the agent for those.

---

## Prerequisites

- GCP project(s) you want to connect
- IAM rights to create service accounts at the project (or
  folder / org) scope and grant them Viewer / Logging Viewer
- For VPC Flow Logs: an existing logging sink, OR rights to
  enable flow logs on the VPC subnets

---

## Step 1 — Create the service account and grant IAM

```bash
PROJECT_ID=<gcp-project-id>

# Service account
gcloud iam service-accounts create csw-cloud-connector \
  --display-name="CSW Cloud Connector" \
  --project="${PROJECT_ID}"

SA_EMAIL="csw-cloud-connector@${PROJECT_ID}.iam.gserviceaccount.com"

# Read-only viewer at project scope
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/viewer"

# Logging viewer for VPC Flow Logs
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/logging.viewer"

# Compute network viewer (more granular than projects/viewer for some releases)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/compute.networkViewer"
```

For multi-project at scale, grant at the **folder** or
**organisation** scope instead:

```bash
gcloud organizations add-iam-policy-binding <ORG-ID> \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/viewer"
```

---

## Step 2 — Allow CSW to impersonate the service account

CSW uses Workload Identity Federation (preferred) or a service
account JSON key (legacy). Federation avoids long-lived keys.

### Option A — Workload Identity Federation (recommended)

```bash
# Create a workload identity pool
gcloud iam workload-identity-pools create csw-pool \
  --location=global \
  --display-name="CSW Connector Pool"

# Create the federated identity provider tied to CSW's principal
gcloud iam workload-identity-pools providers create-oidc csw-provider \
  --location=global \
  --workload-identity-pool=csw-pool \
  --issuer-uri="https://<csw-issuer-uri-from-CSW-UI>" \
  --attribute-mapping="google.subject=assertion.sub" \
  --attribute-condition="assertion.sub == '<CSW-CONNECTOR-IDENTITY>'"

# Grant the federated identity permission to impersonate the SA
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/<PROJECT-NUMBER>/locations/global/workloadIdentityPools/csw-pool/*"
```

Capture the workload identity pool path — paste into CSW.

### Option B — Service account JSON key (legacy)

```bash
gcloud iam service-accounts keys create /tmp/csw-sa-key.json \
  --iam-account="${SA_EMAIL}"
```

Treat the JSON file as a long-lived credential. Upload it to CSW
and **delete the local copy immediately**. Rotate annually.

> Workload Identity Federation is strongly preferred. JSON keys
> remain valid until manually rotated and have been the
> root cause of recurring credential-leak incidents in Cisco's
> field experience.

---

## Step 3 — Enable VPC Flow Logs (if you want flow telemetry)

Per subnet:

```bash
gcloud compute networks subnets update <subnet-name> \
  --region=<region> \
  --enable-flow-logs \
  --logging-aggregation-interval=interval-5-sec \
  --logging-flow-sampling=0.5 \
  --logging-metadata=include-all
```

Sampling 0.5 (half of flows) is a reasonable production starting
point — full sampling on a busy subnet can be expensive.

---

## Step 4 — Configure the connector in the CSW UI

1. Log into the CSW UI
2. Navigate to *Manage → External Orchestrators → GCP*
3. Click *Add Connector*
4. Provide:
   - Connector name (e.g., `gcp-prod-project-XYZ`)
   - GCP project ID (or organisation ID for org-scoped sync)
   - Authentication: workload identity pool path (Option A) OR
     upload the service account JSON (Option B)
5. Click *Test Connection*. CSW impersonates the SA and validates
   `compute.instances.list` and related permissions.
6. Save. First inventory sync runs within an hour.

---

## Step 5 — Verify

- *Organize → Inventory → Filter by `cloud_project = <project-id>`*
- *Investigate → Flows → Filter by source/dest in the subnet*
- *Manage → External Orchestrators → click the connector* — last
  successful sync timestamp

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| "Test Connection" fails with `iam.serviceAccounts.signBlob denied` | Federated identity not authorised to impersonate the SA | Re-check the `roles/iam.workloadIdentityUser` binding |
| Inventory shows GKE clusters but no per-pod attribution | Expected — connector sees the cluster, the K8s sensor sees the pods | Deploy the K8s sensor (see `../kubernetes/`) for per-pod data |
| Flow logs missing despite `--enable-flow-logs` | Default sink doesn't include flow logs | Add a Cloud Logging sink with filter `resource.type="gce_subnetwork" AND log_id("compute.googleapis.com/vpc_flows")` |
| Connector flagged as security-finding ("external service account impersonation") | Standard GCP audit pattern | Document the federated identity scope; provide audit evidence |
| Org-scoped Viewer surfaces inventory the security team isn't allowed to see | Over-broad scope | Move to folder-scoped grants per business unit |

---

## See also

- [`05-comparison-matrix.md`](./05-comparison-matrix.md)
- [`../cloud/03-gcp-startup-script.md`](../cloud/03-gcp-startup-script.md) — agent path for GCE
- [`../kubernetes/03-eks-aks-gke.md`](../kubernetes/03-eks-aks-gke.md) — GKE notes for the agent path
