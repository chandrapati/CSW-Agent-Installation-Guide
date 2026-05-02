################################################################################
# aws-userdata.tf — Example Terraform: install CSW agent at first boot via S3.
#
# Runnable shape, not a production module. Adapt names, IAM, and CIDRs to your
# environment. See cloud/01-aws-userdata.md and cloud/04-terraform.md for context.
################################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
}

variable "region"               { default = "us-east-1" }
variable "vpc_id"               { type = string }
variable "subnet_id"            { type = string }
variable "csw_agent_s3_uri"     { type = string }
variable "csw_ca_s3_uri"        { type = string }
variable "csw_ssm_param_name"   { type = string }   # /csw/activation-key/prod-web
variable "csw_scope"            { type = string }   # prod:web-tier
variable "csw_cluster_fqdn"     { type = string }   # csw.example.com (informational)

data "aws_caller_identity" "current" {}

# ----- IAM: instance role permitting agent payload + activation key reads -----
data "aws_iam_policy_document" "instance_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "csw" {
  name               = "csw-instance-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
  tags               = { Purpose = "Cisco Secure Workload sensor" }
}

data "aws_iam_policy_document" "csw_inline" {
  statement {
    sid     = "ReadAgentPayloadFromS3"
    actions = ["s3:GetObject"]
    resources = [
      replace(var.csw_agent_s3_uri, "s3://", "arn:aws:s3:::"),
      replace(var.csw_ca_s3_uri,    "s3://", "arn:aws:s3:::"),
    ]
  }
  statement {
    sid       = "ReadActivationKeyFromSSM"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.csw_ssm_param_name}"]
  }
  statement {
    sid       = "TagSelf"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*"]
  }
}

resource "aws_iam_role_policy" "csw" {
  role   = aws_iam_role.csw.id
  policy = data.aws_iam_policy_document.csw_inline.json
}

resource "aws_iam_instance_profile" "csw" {
  name = "csw-instance-profile"
  role = aws_iam_role.csw.name
}

# ----- AMI: latest Amazon Linux 2023 ------------------------------------------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ----- user_data --------------------------------------------------------------
locals {
  user_data = templatefile("${path.module}/../cloud-init/aws-csw-rhel9.sh", {})
}

# ----- Launch template (suitable for ASG) -------------------------------------
resource "aws_launch_template" "web" {
  name_prefix   = "web-csw-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t3.medium"

  iam_instance_profile {
    arn = aws_iam_instance_profile.csw.arn
  }

  metadata_options {
    http_tokens                 = "required"   # IMDSv2 only
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
    instance_metadata_tags      = "enabled"
  }

  network_interfaces {
    associate_public_ip_address = false
    subnet_id                   = var.subnet_id
    security_groups             = [aws_security_group.web.id]
  }

  user_data = base64encode(local.user_data)

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name             = "web"
      csw_scope        = var.csw_scope
      csw_cluster_fqdn = var.csw_cluster_fqdn
    }
  }
}

# Minimal egress-only security group (open 443 outbound to anywhere — tighten
# in production to the actual cluster CIDR / FQDN-resolved set)
resource "aws_security_group" "web" {
  name   = "csw-web-egress"
  vpc_id = var.vpc_id

  egress {
    description = "HTTPS to Cisco Secure Workload cluster"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # Replace with cluster's specific CIDR(s) in production
  }

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "NTP"
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "launch_template_id" {
  value = aws_launch_template.web.id
}
