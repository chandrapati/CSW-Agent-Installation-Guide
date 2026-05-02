################################################################################
# golden-ami-csw.pkr.hcl — Pattern X: bake CSW agent binaries into a Golden AMI;
# defer activation to first boot via a oneshot systemd service.
#
# See cloud/05-golden-ami.md for the full walkthrough.
################################################################################

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.2"
    }
  }
}

variable "region"               { default = "us-east-1" }
variable "base_ami_owner"       { default = "amazon" }
variable "base_ami_name_filter" { default = "al2023-ami-*-x86_64" }
variable "csw_agent_s3_uri"     { default = "s3://internal-csw-agents/linux/el9/tet-sensor-3.x.y.z-1.el9.x86_64.rpm" }
variable "csw_ca_s3_uri"        { default = "s3://internal-csw-agents/linux/ca.pem" }
variable "csw_agent_version"    { default = "3.x.y.z" }
variable "ami_share_account_ids" {
  type    = list(string)
  default = []
}

source "amazon-ebs" "rhel9_csw" {
  region          = var.region
  instance_type   = "t3.medium"
  ssh_username    = "ec2-user"

  ami_name        = "internal-rhel9-csw-${var.csw_agent_version}-{{timestamp}}"
  ami_description = "RHEL 9 with CSW sensor v${var.csw_agent_version} pre-installed"

  source_ami_filter {
    filters = {
      name                = var.base_ami_name_filter
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = [var.base_ami_owner]
    most_recent = true
  }

  iam_instance_profile = "packer-builder-csw"   # has s3:GetObject for the agent bucket

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  ami_users = var.ami_share_account_ids

  tags = {
    Name              = "rhel9-csw-${var.csw_agent_version}"
    csw_agent_version = var.csw_agent_version
    base_lineage      = "amazon/al2023"
    baked_by          = "packer"
  }
}

build {
  name    = "rhel9-csw-golden"
  sources = ["source.amazon-ebs.rhel9_csw"]

  # Patch baseline + ensure kernel headers
  provisioner "shell" {
    inline = [
      "sudo dnf upgrade -y",
      "sudo dnf install -y kernel-headers-$(uname -r) || true",
    ]
  }

  # Install the CSW agent (Pattern X — defer activation)
  provisioner "shell" {
    inline = [
      "set -euxo pipefail",
      "sudo mkdir -p /etc/tetration && sudo chmod 750 /etc/tetration",
      "sudo aws s3 cp ${var.csw_agent_s3_uri} /tmp/tet-sensor.rpm",
      "sudo aws s3 cp ${var.csw_ca_s3_uri} /etc/tetration/ca.pem",
      "sudo dnf install -y /tmp/tet-sensor.rpm",
      "sudo rm -f /tmp/tet-sensor.rpm",
      # Mask tetd so the build VM does NOT register itself with the cluster
      "sudo systemctl disable tetd",
      "sudo systemctl mask tetd",
    ]
  }

  # Drop a first-boot oneshot service that activates per-instance
  provisioner "shell" {
    inline = [
      "sudo bash -c 'cat > /usr/local/sbin/csw-first-boot.sh' <<'SCRIPT'",
      "#!/bin/bash",
      "set -euxo pipefail",
      "exec > /var/log/csw-first-boot.log 2>&1",
      "TOKEN=$(curl -s -X PUT \"http://169.254.169.254/latest/api/token\" -H \"X-aws-ec2-metadata-token-ttl-seconds: 21600\")",
      "REGION=$(curl -s -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/placement/region)",
      "SSM_NAME=$(curl -s -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/tags/instance/csw_scope_param || echo /csw/activation-key/default)",
      "CSW_SCOPE=$(curl -s -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/tags/instance/csw_scope || echo default)",
      "ACTIVATION_KEY=$(aws ssm get-parameter --name \"$SSM_NAME\" --with-decryption --region \"$REGION\" --query Parameter.Value --output text)",
      "cat > /etc/tetration/sensor.conf <<EOF",
      "ACTIVATION_KEY=$ACTIVATION_KEY",
      "SCOPE=$CSW_SCOPE",
      "EOF",
      "chmod 640 /etc/tetration/sensor.conf",
      "systemctl unmask tetd",
      "systemctl enable --now tetd",
      "touch /var/lib/csw-activated",
      "SCRIPT",

      "sudo chmod 755 /usr/local/sbin/csw-first-boot.sh",

      "sudo bash -c 'cat > /etc/systemd/system/csw-first-boot.service' <<'UNIT'",
      "[Unit]",
      "Description=Cisco Secure Workload first-boot activation",
      "After=cloud-init-local.service network-online.target",
      "Wants=network-online.target",
      "ConditionPathExists=!/var/lib/csw-activated",
      "",
      "[Service]",
      "Type=oneshot",
      "ExecStart=/usr/local/sbin/csw-first-boot.sh",
      "RemainAfterExit=yes",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "UNIT",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable csw-first-boot.service",
    ]
  }

  # Sanity check
  provisioner "shell" {
    inline = [
      "rpm -q tet-sensor",
      "ls -la /etc/tetration/",
      "systemctl is-enabled csw-first-boot.service",
      "systemctl is-enabled tetd || true",   # masked, ok
    ]
  }
}
