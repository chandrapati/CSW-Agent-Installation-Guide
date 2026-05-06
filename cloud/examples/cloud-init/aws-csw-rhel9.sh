#!/bin/bash
# AWS EC2 user_data — install CSW sensor on RHEL 9 / Amazon Linux 2023.
# Pattern A from cloud/01-aws-userdata.md (payload from private S3 bucket).
#
# The instance must launch with an instance role that allows:
#   - s3:GetObject on the agent + CA artefacts
#   - ssm:GetParameter on the activation-key parameter
# IMDSv2 is required (instance-level metadata-options should mandate it).

set -euxo pipefail
exec > /var/log/csw-userdata.log 2>&1

readonly AGENT_S3_URI="${AGENT_S3_URI:-s3://internal-csw-agents/linux/el9/tet-sensor-3.10.1.45-1.el9.x86_64.rpm}"
readonly CA_S3_URI="${CA_S3_URI:-s3://internal-csw-agents/linux/ca.pem}"
readonly SSM_PARAM_NAME="${SSM_PARAM_NAME:-/csw/activation-key/prod-web}"
readonly CSW_SCOPE="${CSW_SCOPE:-prod:web-tier}"

# IMDSv2 token
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)

# Pull payload from S3
aws s3 cp "$AGENT_S3_URI" /tmp/tet-sensor.rpm --region "$REGION"

mkdir -p /etc/tetration && chmod 750 /etc/tetration
aws s3 cp "$CA_S3_URI" /etc/tetration/ca.pem --region "$REGION" --quiet || true

# Activation key from SSM
ACTIVATION_KEY=$(aws ssm get-parameter \
  --name "$SSM_PARAM_NAME" \
  --with-decryption \
  --region "$REGION" \
  --query Parameter.Value \
  --output text)

cat > /etc/tetration/sensor.conf <<EOF
ACTIVATION_KEY=$ACTIVATION_KEY
SCOPE=$CSW_SCOPE
EOF
chmod 640 /etc/tetration/sensor.conf

# Install + enable
dnf install -y /tmp/tet-sensor.rpm
systemctl enable --now csw-agent

rm -f /tmp/tet-sensor.rpm

echo "CSW sensor install complete at $(date -u +%FT%TZ)"
