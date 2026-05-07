#!/bin/bash
# AWS EC2 user_data — install CSW sensor on RHEL 9 / Amazon Linux 2023.
# Pattern A from cloud/01-aws-userdata.md (CSW-generated installer
# script from private S3 bucket).
#
# The instance must launch with an instance role that allows:
#   - s3:GetObject on the CSW-generated installer script
# IMDSv2 is required (instance-level metadata-options should mandate it).

set -euxo pipefail
exec > /var/log/csw-userdata.log 2>&1

readonly INSTALLER_S3_URI="${INSTALLER_S3_URI:-s3://internal-csw-agents/linux/tetration_linux_installer.sh}"

# IMDSv2 token
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)

# Pull Cisco-generated installer script from S3. Treat this script
# as a secret because it embeds activation material.
aws s3 cp "$INSTALLER_S3_URI" /tmp/tetration_linux_installer.sh --region "$REGION"

# Install + enable
chmod 700 /tmp/tetration_linux_installer.sh
bash /tmp/tetration_linux_installer.sh

rm -f /tmp/tetration_linux_installer.sh

echo "CSW sensor install complete at $(date -u +%FT%TZ)"
