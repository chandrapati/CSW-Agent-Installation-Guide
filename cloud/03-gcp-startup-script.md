# GCP — Install via GCE Startup Script

GCP equivalent of AWS `user_data` and Azure `custom_data`. The
GCE instance metadata key `startup-script` (or
`startup-script-url`) runs at boot. Works for any IaC tool
(Terraform, Deployment Manager, gcloud) and for any base image
that supports the GCE startup-script daemon.

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- A GCE instance with the GCE startup-script daemon
  (default for GCP-published images)
- Outbound 443 from the instance to the CSW cluster (default GCP
  egress allows this; firewall rules or Cloud NAT may apply)
- The CSW agent payload reachable somewhere — three patterns:
  - **Pattern A (recommended)**: a private GCS bucket holding
    the agent payload and CA chain
  - **Pattern B**: workload reaches the cluster directly and
    runs the CSW-generated installer script
  - **Pattern C**: pre-baked GCE custom image (the GCP analogue
    of Golden AMI)

---

## Pattern A — payload from a private GCS bucket

### One-time setup

```bash
# Create the bucket (uniform bucket-level access, with org-policy
# preventing public access)
gsutil mb -p my-project -l us-central1 -b on gs://internal-csw-agents/

# Upload the package + CA
gsutil cp tet-sensor-3.x.y.z-1.el9.x86_64.rpm \
  gs://internal-csw-agents/linux/el9/

gsutil cp ca.pem gs://internal-csw-agents/linux/

# Grant the VM's service account read access
gcloud storage buckets add-iam-policy-binding gs://internal-csw-agents \
  --member="serviceAccount:csw-vm-sa@my-project.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

### `startup-script` (Linux — RHEL family)

The startup script is set as instance metadata at launch. Embed
it inline (`startup-script`) for short scripts, or host it in
GCS (`startup-script-url`) for longer ones.

```bash
#!/bin/bash
set -euxo pipefail

# Get an OAuth token from the metadata server (the VM's service account)
TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

# Pull the agent package
curl -s -L -H "Authorization: Bearer $TOKEN" \
  -o /tmp/tet-sensor.rpm \
  "https://storage.googleapis.com/internal-csw-agents/linux/el9/tet-sensor-3.x.y.z-1.el9.x86_64.rpm"

# Pull the CA
mkdir -p /etc/tetration && chmod 750 /etc/tetration
curl -s -L -H "Authorization: Bearer $TOKEN" \
  -o /etc/tetration/ca.pem \
  "https://storage.googleapis.com/internal-csw-agents/linux/ca.pem"

# Get activation key from Secret Manager
ACTIVATION_KEY=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "https://secretmanager.googleapis.com/v1/projects/my-project/secrets/csw-activation-key-prod-web/versions/latest:access" \
  | python3 -c 'import sys,json,base64; print(base64.b64decode(json.load(sys.stdin)["payload"]["data"]).decode())')

cat > /etc/tetration/sensor.conf <<EOF
ACTIVATION_KEY=$ACTIVATION_KEY
SCOPE=prod:web-tier
EOF
chmod 640 /etc/tetration/sensor.conf

# Install
dnf install -y /tmp/tet-sensor.rpm

# Start
systemctl enable --now csw-agent
```

### Setting the metadata at instance launch

```bash
# Inline
gcloud compute instances create web-01 \
  --image-family=rhel-9 \
  --image-project=rhel-cloud \
  --metadata-from-file=startup-script=./install-csw.sh \
  --service-account=csw-vm-sa@my-project.iam.gserviceaccount.com \
  --scopes=cloud-platform \
  --zone=us-central1-a

# From GCS
gsutil cp install-csw.sh gs://internal-csw-agents/scripts/install-csw.sh

gcloud compute instances create web-01 \
  --image-family=rhel-9 \
  --image-project=rhel-cloud \
  --metadata=startup-script-url=gs://internal-csw-agents/scripts/install-csw.sh \
  --service-account=csw-vm-sa@my-project.iam.gserviceaccount.com \
  --scopes=cloud-platform \
  --zone=us-central1-a
```

### Why this pattern

- **No secrets in metadata**: the activation key lives in
  Secret Manager; only the VM's service account can fetch it.
- **VPC Service Controls**: a production setup typically wraps
  Storage and Secret Manager in a perimeter; the VM's service
  account is the only identity inside the perimeter able to
  pull payload + key.
- **Versioned**: GCS object names include the version string;
  upgrades are an object copy and a metadata update.

### IAM grant patterns

The VM's service account needs:

```bash
# Read agent payload from the bucket
gcloud projects add-iam-policy-binding my-project \
  --member="serviceAccount:csw-vm-sa@my-project.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer" \
  --condition=expression='resource.name.startsWith("projects/_/buckets/internal-csw-agents")',title=csw_agent_pull,description='allow CSW VMs to pull agent payload'

# Access the activation-key secret
gcloud secrets add-iam-policy-binding csw-activation-key-prod-web \
  --member="serviceAccount:csw-vm-sa@my-project.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

---

## Pattern B — CSW-generated installer (no GCS prep)

If the workload has direct egress to the CSW cluster, ship the
CSW-generated installer in `startup-script` directly. Same
trade-offs as the AWS / Azure Pattern B.

---

## Pattern C — payload baked into a GCE custom image

The recommended pattern at scale. Build a custom image with
Packer (or `gcloud compute images create --source-disk ...`) that
has the agent installed and the activation handled at first boot.
See the Golden AMI doc for the conceptual pattern; the GCP
implementation follows the same shape.

---

## Wave-based rollout

In Terraform-managed estates, wave-based rollout in GCP typically
means rolling the **Managed Instance Group** (MIG):

```hcl
resource "google_compute_region_instance_group_manager" "web" {
  # ...
  update_policy {
    type                  = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 3
    max_unavailable_fixed = 0
  }
}
```

Per environment:

| Wave | Mechanism |
|---|---|
| Lab | Apply in lab project; replace a few VMs |
| Stage | Apply in stage project |
| Prod canary | Apply with `target_size = 1` for a canary MIG |
| Prod rest | Apply across remaining MIGs with small `max_surge` and `max_unavailable=0` |

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Startup script doesn't run | Disabled in instance template / not applied | Confirm `enable-oslogin` doesn't conflict; check `/var/log/syslog` for `google-startup-scripts` daemon entries |
| `gs://` URL in `startup-script-url` returns 403 | VM SA missing `roles/storage.objectViewer` on the bucket | Add the binding; SA propagation takes a moment |
| Secret Manager fetch returns 403 | VM SA missing `roles/secretmanager.secretAccessor` on the secret | Add the binding |
| OAuth scope error during `curl` to Storage | VM launched with `--scopes=storage-ro` instead of `cloud-platform` | Use `cloud-platform` and rely on IAM bindings; or include `storage-ro` and `cloud-platform` |
| Startup script runs every boot | This is by-design (key `startup-script` runs every boot) | Use the GCE one-time startup pattern: have the script `touch /var/lib/csw-installed` and exit early if that file exists |

---

## Idempotent wrapper for repeat-boot scenarios

```bash
#!/bin/bash
set -euxo pipefail

if [[ -f /var/lib/csw-installed ]]; then
  echo "CSW agent already installed; nothing to do."
  exit 0
fi

# ... install commands here ...

touch /var/lib/csw-installed
```

This is a small but critical hygiene step in GCP that the AWS /
Azure equivalents don't strictly need (those run `user_data` /
`custom_data` only on first boot).

---

## See also

- [`./examples/cloud-init/gcp-csw-rhel9.sh`](./examples/cloud-init/gcp-csw-rhel9.sh) — runnable startup script
- [`04-terraform.md`](./04-terraform.md) — multi-cloud IaC patterns
- [`05-golden-ami.md`](./05-golden-ami.md) — image-baked pattern (the AWS doc; GCP custom images follow the same conceptual shape)
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md)
