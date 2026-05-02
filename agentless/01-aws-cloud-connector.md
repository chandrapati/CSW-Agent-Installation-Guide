# Agentless — AWS Cloud Connector

CSW pulls inventory and (optionally) VPC Flow Logs from each
AWS account it's connected to. Authentication is via a
**cross-account IAM role** that CSW assumes; no agent runs on
AWS workloads.

---

## What you get

- Continuous EC2 / ECS / EKS / RDS / ELB / S3 inventory across
  the connected accounts
- Tags and metadata enrichment (region, AZ, security groups,
  network interfaces, attached IAM role)
- VPC Flow Log ingest (when the flow-log destination is
  shareable to CSW)
- Reconciliation against the host-agent inventory: CSW shows
  which EC2 instances have an agent and which don't

## What you don't get

- Process attribution per flow
- Software inventory or CVE lookup
- Workload-side enforcement
- Sub-flow-log latency on flow data

---

## Prerequisites

- AWS account(s) you want to connect — production, DR, sandbox,
  partner-shared, etc.
- IAM rights to create roles, policies, and (for flow logs) S3
  buckets / CloudWatch log groups in each account
- The CSW connector's own AWS account ID and external ID — get
  these from the CSW UI when you start the connector setup
  wizard

---

## Step 1 — Create the cross-account IAM role per account

In each AWS account you want to connect:

```bash
# Trust policy — permits the CSW connector's AWS account to assume the role
cat > csw-connector-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::<CSW-CONNECTOR-ACCOUNT-ID>:root"
    },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {
        "sts:ExternalId": "<EXTERNAL-ID-FROM-CSW-UI>"
      }
    }
  }]
}
EOF

aws iam create-role \
  --role-name CSWCloudConnector \
  --assume-role-policy-document file://csw-connector-trust.json \
  --description "CSW Cloud Connector — read-only inventory + flow logs"

# Permission policy — least-privilege read-only
cat > csw-connector-permissions.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "InventoryRead",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "elasticloadbalancing:Describe*",
        "rds:Describe*",
        "ecs:Describe*",
        "ecs:List*",
        "eks:Describe*",
        "eks:List*",
        "s3:GetBucketTagging",
        "s3:ListAllMyBuckets",
        "iam:ListRoles",
        "iam:GetRole",
        "tag:GetResources"
      ],
      "Resource": "*"
    },
    {
      "Sid": "FlowLogConfigRead",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeFlowLogs",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Sid": "FlowLogS3Read",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::<flow-log-bucket-name>",
        "arn:aws:s3:::<flow-log-bucket-name>/*"
      ]
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name CSWCloudConnector \
  --policy-name CSWReadOnly \
  --policy-document file://csw-connector-permissions.json
```

Capture the role ARN — you'll paste it into the CSW UI:

```bash
aws iam get-role --role-name CSWCloudConnector --query Role.Arn --output text
```

> **Why an external ID?** Standard AWS practice for cross-account
> access. The external ID is a shared secret unique to your CSW
> tenant; it prevents the
> [confused-deputy problem](https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html)
> where another customer of CSW could assume your role.

---

## Step 2 — Enable VPC Flow Logs (if you want flow telemetry)

VPC Flow Logs are required for the connector to provide
flow-log–tier visibility. If you already have them enabled
elsewhere, point the connector at the existing destination.
Otherwise:

```bash
# Option A — flow logs to an S3 bucket (cheaper for large VPCs)
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxxxxx \
  --traffic-type ALL \
  --log-destination-type s3 \
  --log-destination "arn:aws:s3:::<flow-log-bucket-name>/AWSLogs/" \
  --log-format '${version} ${account-id} ${interface-id} ${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${packets} ${bytes} ${start} ${end} ${action} ${log-status} ${vpc-id} ${subnet-id} ${instance-id} ${tcp-flags} ${type} ${pkt-srcaddr} ${pkt-dstaddr}'

# Option B — flow logs to CloudWatch Logs (better for low-volume VPCs and ad-hoc queries)
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs/<vpc-id> \
  --deliver-logs-permission-arn arn:aws:iam::<account-id>:role/flowlogsDeliveryRole
```

Confirm the connector role has `s3:GetObject` on the bucket (Option
A) or `logs:GetLogEvents` on the log group (Option B). The
permissions JSON in Step 1 covers both.

> **Cost note.** VPC Flow Logs in production VPCs can produce
> significant data volume and storage cost. Sample if cost is a
> concern (`--max-aggregation-interval 60` plus `LogFormat`
> trimming); CSW can ingest sampled data with reduced fidelity.

---

## Step 3 — Configure the connector in the CSW UI

1. Log into the CSW UI
2. Navigate to *Manage → External Orchestrators → AWS* (or
   release-equivalent)
3. Click *Add Connector*
4. Provide:
   - Connector name (e.g., `aws-prod-account-12345`)
   - The cross-account role ARN from Step 1
   - The external ID from CSW (must match Step 1's trust policy)
   - The AWS account ID + region(s) to scan
   - Flow log source — S3 bucket / CloudWatch log group from Step 2
5. Click *Test Connection*. CSW assumes the role and validates
   `Describe*` access. If it fails, check the trust policy's
   external ID and the role's permission policy.
6. Save. The first inventory sync runs within an hour.

---

## Step 4 — Verify

- *Organize → Inventory → Filter by `cloud_account = <account-id>`*
  — every EC2 instance the role can see should appear
- *Investigate → Flows → Filter by source/dest in the VPC* — flow
  records appear within 10–15 minutes of flow log delivery
- *Manage → External Orchestrators → click the connector* — last
  successful sync timestamp should be recent

---

## Multi-account at scale (Organisations)

For dozens or hundreds of AWS accounts, don't deploy the role
per-account by hand. Two patterns:

- **Service-Managed CloudFormation StackSet** in the management
  account, deploying the role + permissions to every member
  account in the org. Roll out per OU; targets new accounts
  automatically as they join.
- **Account Factory for Terraform (AFT)** with a per-account
  module that ships the role.

In CSW, add each connector individually (one per account). For
hundreds of accounts, ask Cisco about the bulk-import API for
connectors — supported in current releases.

---

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| "Test Connection" fails with `AccessDenied` | External ID mismatch between role trust and CSW UI | Re-check both; the value is case-sensitive |
| Inventory sync succeeds but flow logs are missing | Flow log destination is S3 in another account; cross-account read not granted | Either deliver flow logs to a bucket in the same account as the role, or grant cross-account `s3:GetObject` |
| Inventory shows EC2 but not RDS / ECS / EKS | Role permission policy missing those services | Update the permission policy and `aws iam put-role-policy` again |
| Connector counts as a security audit finding ("cross-account role from external party") | Standard AWS audit pattern | Document the external ID and the connector's least-privilege scope; provide audit evidence |
| Connector goes silent after AWS Organisations SCP change | An SCP at the OU level denied `sts:AssumeRole` for external principals | Reconcile the SCP exception list; the CSW connector account ID needs explicit allow |

---

## See also

- [`05-comparison-matrix.md`](./05-comparison-matrix.md)
- [`../cloud/`](../cloud/) — agent path for cloud VMs
- [`../kubernetes/03-eks-aks-gke.md`](../kubernetes/03-eks-aks-gke.md) — EKS-specific notes for the agent path
