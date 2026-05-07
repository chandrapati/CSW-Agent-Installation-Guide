# AWS — Install via EC2 `user_data`

Embed the CSW agent install in the EC2 instance's `user_data`
field so it runs at first boot. Works for any IaC tool
(Terraform, CloudFormation, CDK, Pulumi) and for any base AMI
that supports `cloud-init`.

> For production fleets, this is typically the **first-month**
> pattern. Once the install is stable, move to a **Golden AMI**
> ([05-golden-ami.md](./05-golden-ami.md)) so launches don't
> wait on the install at boot.

---

## Prerequisites

- All items from [`../docs/01-prerequisites.md`](../docs/01-prerequisites.md)
- An EC2 instance with `cloud-init` enabled (the default for
  Amazon Linux, Ubuntu, RHEL, SUSE official AMIs)
- Outbound 443 from the instance to the CSW cluster (Internet
  Gateway, NAT Gateway, VPC peering, or Direct Connect)
- The CSW installer reachable somewhere — three patterns:
  - **Pattern A (recommended)**: a private S3 bucket holding the
    CSW-generated `tetration_linux_installer.sh` from your cluster
  - **Pattern B**: workload reaches the cluster directly and
    runs the CSW-generated installer script (the script
    self-fetches the package from the cluster)
  - **Pattern C**: pre-packaged AMI with payload baked in (this
    is essentially a half-step toward Golden AMI)

---

## Pattern A — CSW-generated installer script from a private S3 bucket

This keeps the Cisco-supported install flow intact while making
the script available through an IAM-controlled private bucket. Do
not split the Cisco package into ad hoc `ca.pem` and
`/etc/tetration/sensor.conf` files; Cisco's installer owns the
site files and activation wiring.

### One-time setup

```bash
# Stage the CSW-generated installer script in a private S3 bucket.
# Treat this script as a secret because it embeds activation material.
aws s3 cp tetration_linux_installer.sh \
  s3://internal-csw-agents/linux/tetration_linux_installer.sh

# Create an IAM policy that allows EC2 instances to read the bucket
cat > csw-agent-pull-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadCSWAgentArtifacts",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::internal-csw-agents",
        "arn:aws:s3:::internal-csw-agents/*"
      ]
    }
  ]
}
EOF

aws iam create-policy --policy-name CSWAgentPull \
  --policy-document file://csw-agent-pull-policy.json

# Attach this policy to the EC2 instance role used by your launch
# template, ASG, or Terraform aws_iam_role
```

### `user_data` script (Amazon Linux 2 / 2023 / RHEL family)

```bash
#!/bin/bash
set -euxo pipefail

# IMDSv2 token (always use IMDSv2 — required by your account baseline)
TOKEN=$(curl -s -X PUT \
  "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

# Pull installer from the internal bucket (instance role grants read)
aws s3 cp \
  s3://internal-csw-agents/linux/tetration_linux_installer.sh \
  /tmp/tetration_linux_installer.sh \
  --region "$REGION"

# Install
chmod 700 /tmp/tetration_linux_installer.sh
bash /tmp/tetration_linux_installer.sh

# Start
systemctl enable --now csw-agent

# Tag the instance with sensor status (helps inventory reconciliation)
aws ec2 create-tags --resources "$INSTANCE_ID" \
  --tags "Key=csw_sensor,Value=installed" \
  --region "$REGION" || true
```

### Why this pattern

- **Versioned**: the S3 object key includes the agent version;
  upgrades are an `aws s3 cp` of a new package + an updated
  `user_data` (or Golden AMI rebuild).
- **Auditable**: S3 access logs show every instance that pulled
  the agent.
- **Air-gap friendly**: if the bucket has a VPC endpoint, no
  internet egress is required for the package payload itself
  (the agent still needs to reach the CSW cluster).
- **Secret-managed**: the activation key lives in SSM Parameter
  Store (encrypted at rest with KMS), not in `user_data`
  (which is visible via the EC2 console).

### Ubuntu / Debian variant

```bash
#!/bin/bash
set -euxo pipefail

apt-get update
apt-get install -y awscli

aws s3 cp \
  s3://internal-csw-agents/linux/ubuntu22/tet-sensor-3.x.y.z-1.ubuntu22_amd64.deb \
  /tmp/tet-sensor.deb

# (rest is the same shape as the RHEL version, with apt instead of dnf)
apt-get install -y /tmp/tet-sensor.deb
systemctl enable --now csw-agent
```

---

## Pattern B — CSW-generated installer (no S3 prep needed)

If the workload has direct egress to the CSW cluster, you can
ship the CSW-generated script as `user_data` directly. Lower
prep cost; less version control over the payload.

### `user_data`

```bash
#!/bin/bash
set -euxo pipefail

# Either embed the entire CSW-generated installer here:
cat > /tmp/install_sensor.sh <<'INSTALLER'
#!/bin/bash
# ... entire contents of the CSW-generated installer ...
INSTALLER
chmod +x /tmp/install_sensor.sh

# Or pull it from your S3 bucket (more maintainable)
# aws s3 cp s3://internal-csw-agents/linux/install_sensor_prod_web.sh \
#   /tmp/install_sensor.sh

/tmp/install_sensor.sh --silent
```

### When to use Pattern B over Pattern A

- **Pilot / first-month POV** where the team isn't ready to
  manage agent versioning in S3 yet
- **Small-fleet accounts** where the per-S3-pull overhead isn't
  worth it
- **One-off remediation** instances spun up to debug

For steady-state production, Pattern A is more durable.

---

## Pattern C — payload baked into a custom AMI

A half-step toward Golden AMI: build a custom AMI from a public
base, run the install commands during the build, snapshot.
`user_data` becomes much simpler — often empty or just a
"verify and re-register if needed" check.

This is the natural evolution of Pattern A once you've validated
the install. See [05-golden-ami.md](./05-golden-ami.md) for the
full Packer-based pattern.

---

## Wave-based rollout for new launches

In a Terraform-managed estate, wave-based rollout typically means:

| Wave | Mechanism |
|---|---|
| Lab | Apply the `user_data` change in your `lab` workspace; Terraform replaces a few instances |
| Stage | Apply in `stage` workspace; replace the stage hosts |
| Prod canary | Apply in `prod` workspace with `count = 1` for the canary auto-scaling group |
| Prod rest | Apply in `prod` workspace; replace remaining instances over a maintenance window |

Coordinate with auto-scaling group rolling-update settings:
`update_policy { rolling_update { max_batch_size = N } }` —
keep N small for production.

---

## Day-2 patching cadence

When CSW publishes a new agent release:

1. Upload the new package to S3 with a new version-tagged key
2. Update the Terraform `user_data` template to reference the
   new key (and bump a `csw_agent_version` variable so the
   change is explicit in PR review)
3. Apply per-environment, in waves
4. Or: rebuild the Golden AMI ([05-golden-ami.md](./05-golden-ami.md)),
   roll the launch templates / ASGs to the new AMI

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `user_data` runs but agent never installs | `cloud-init` ran before network was up; package fetch failed silently | Add `set -euxo pipefail` at the top so failures fail loudly; check `/var/log/cloud-init-output.log` |
| `aws s3 cp` fails with `403` | Instance role missing `CSWAgentPull` policy | Attach the policy; instance metadata caches IAM creds for 6 h, may need fresh launch |
| Activation key visible in `user_data` console output | Key was hardcoded in the script | Move to SSM Parameter Store with `--with-decryption`; never hardcode in `user_data` |
| Agent installs but registers under wrong scope | `sensor.conf` script populated the wrong `SCOPE` value | Confirm the SSM parameter / template variable for the launch template |
| Auto-scaling event lag (instance takes 90+ seconds to be "ready") | First-boot install takes time | Move to Golden AMI to remove the install from boot |

Full troubleshooting in
[`../operations/06-troubleshooting.md`](../operations/06-troubleshooting.md).

---

## See also

- Terraform example intentionally removed until it can be rebuilt
  around the CSW-generated installer-script flow.
- [`./examples/cloud-init/aws-csw-rhel9.sh`](./examples/cloud-init/aws-csw-rhel9.sh) — runnable user_data
- [`04-terraform.md`](./04-terraform.md) — multi-cloud IaC patterns
- [`05-golden-ami.md`](./05-golden-ami.md) — image-baked alternative
- [`../operations/04-upgrade.md`](../operations/04-upgrade.md)
