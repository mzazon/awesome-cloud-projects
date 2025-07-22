# =========================================================================
# AWS EC2 Instances Securely with Systems Manager - Terraform Configuration
# =========================================================================
# This configuration creates a secure EC2 instance managed through AWS Systems Manager
# without requiring SSH keys, bastion hosts, or inbound security group rules.
# The solution demonstrates zero-trust network security principles.

terraform {
  # Enforce minimum Terraform version for stability
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local variables for consistent resource naming and tagging
locals {
  name_prefix = "${var.project_name}-${random_id.suffix.hex}"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "SystemsManagerDemo"
    Recipe      = "ec2-instances-securely-systems-manager"
  }
}

# =========================================================================
# DATA SOURCES - Existing AWS Infrastructure
# =========================================================================

# Use default VPC (most AWS accounts have a default VPC)
data "aws_vpc" "default" {
  default = true
}

# Get first available subnet in the default VPC
data "aws_subnet" "default" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = data.aws_availability_zones.available.names[0]
}

# Get available availability zones in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Get latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# =========================================================================
# IAM RESOURCES - EC2 Instance Role for Systems Manager
# =========================================================================

# IAM role that allows EC2 instances to assume Systems Manager permissions
resource "aws_iam_role" "ssm_instance_role" {
  name = "${local.name_prefix}-ssm-instance-role"
  
  # Trust relationship allowing EC2 service to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ssm-instance-role"
    Type = "IAMRole"
  })
}

# Attach AWS managed policy for Systems Manager core functionality
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ssm_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Optional: Attach CloudWatch Agent policy if enhanced monitoring is desired
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count      = var.enable_cloudwatch_agent ? 1 : 0
  role       = aws_iam_role.ssm_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM instance profile - required to attach IAM roles to EC2 instances
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "${local.name_prefix}-ssm-instance-profile"
  role = aws_iam_role.ssm_instance_role.name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ssm-instance-profile"
    Type = "IAMInstanceProfile"
  })
}

# =========================================================================
# SECURITY GROUP - Zero Inbound Access Configuration
# =========================================================================

# Security group with no inbound rules - demonstrates zero-trust networking
resource "aws_security_group" "ssm_secure" {
  name_prefix = "${local.name_prefix}-ssm-secure-"
  description = "Security group for SSM-managed instance with no inbound access"
  vpc_id      = data.aws_vpc.default.id

  # Allow all outbound traffic (required for Systems Manager communication)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic for Systems Manager communication"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ssm-secure-sg"
    Type = "SecurityGroup"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =========================================================================
# EC2 INSTANCE - Systems Manager Enabled Server
# =========================================================================

# EC2 instance configured for Systems Manager access
resource "aws_instance" "secure_server" {
  # Use the selected AMI based on operating system preference
  ami           = var.operating_system == "amazon-linux" ? data.aws_ami.amazon_linux.id : data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = data.aws_subnet.default.id
  
  # Attach IAM instance profile for Systems Manager permissions
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  
  # Use the restrictive security group (no inbound access)
  vpc_security_group_ids = [aws_security_group.ssm_secure.id]
  
  # Enable detailed monitoring for better observability
  monitoring = var.enable_detailed_monitoring
  
  # Associate public IP only if explicitly requested
  associate_public_ip_address = var.assign_public_ip

  # User data script to ensure Systems Manager agent is running
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    operating_system = var.operating_system
    log_group_name   = var.enable_session_logging ? aws_cloudwatch_log_group.session_logs[0].name : ""
  }))

  # Comprehensive tagging for resource management and cost allocation
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secure-server"
    Type = "EC2Instance"
    OS   = var.operating_system
  })

  # Use instance tags for volume tagging as well
  volume_tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secure-server-root"
    Type = "EBSVolume"
  })

  # Ensure IAM instance profile is fully configured before instance creation
  depends_on = [
    aws_iam_role_policy_attachment.ssm_managed_instance_core,
    aws_iam_instance_profile.ssm_instance_profile
  ]
}

# =========================================================================
# CLOUDWATCH LOGGING - Session Audit Trail
# =========================================================================

# CloudWatch Log Group for Systems Manager session logging
resource "aws_cloudwatch_log_group" "session_logs" {
  count = var.enable_session_logging ? 1 : 0
  
  name              = "/aws/ssm/sessions/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  
  # Optional: Enable encryption with customer-managed KMS key
  kms_key_id = var.kms_key_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-session-logs"
    Type = "CloudWatchLogGroup"
  })
}

# =========================================================================
# USER DATA SCRIPT - Systems Manager Agent Configuration
# =========================================================================

# Template file for user data script
resource "local_file" "user_data_script" {
  filename = "${path.module}/user_data.sh"
  content  = <<-EOF
#!/bin/bash

# User data script for Systems Manager enabled EC2 instance
# This script ensures the Systems Manager agent is running and configured

set -e  # Exit on any error

# Log all output for debugging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting user data script execution at $(date)"

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_message "Configuring instance for Systems Manager..."

%{if operating_system == "amazon-linux"}
# Amazon Linux 2023 configuration
log_message "Configuring Amazon Linux 2023"

# Update system packages
dnf update -y

# Install additional packages if needed
dnf install -y htop wget curl

# Systems Manager agent is pre-installed and auto-starts on Amazon Linux 2023
# Verify it's running
systemctl status amazon-ssm-agent
systemctl enable amazon-ssm-agent

%{else}
# Ubuntu 22.04 configuration
log_message "Configuring Ubuntu 22.04"

# Update package index
apt-get update -y

# Install additional packages
apt-get install -y htop wget curl

# Install Systems Manager agent (if not already installed)
if ! systemctl is-active --quiet amazon-ssm-agent; then
    log_message "Installing Systems Manager agent"
    wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.deb
    dpkg -i amazon-ssm-agent.deb
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
fi

%{endif}

# Configure CloudWatch Logs agent if session logging is enabled
%{if log_group_name != ""}
log_message "Configuring CloudWatch Logs for session logging"

# Create CloudWatch agent configuration
cat << 'CWCONFIG' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/amazon/ssm/audits/audit-*.log",
                        "log_group_name": "${log_group_name}",
                        "log_stream_name": "{instance_id}/ssm-audit",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    }
}
CWCONFIG

# Start CloudWatch agent if installed
if command -v /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl &> /dev/null; then
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
        -s
fi
%{endif}

# Create a simple web application for testing (as shown in recipe)
log_message "Setting up test web application"

%{if operating_system == "amazon-linux"}
# Install and configure nginx on Amazon Linux
dnf install -y nginx
systemctl enable nginx
systemctl start nginx

# Create custom index page
cat << 'HTMLCONTENT' > /usr/share/nginx/html/index.html
<!DOCTYPE html>
<html>
<head>
    <title>Systems Manager Managed Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
        .container { background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .success { color: #28a745; }
        .info { color: #17a2b8; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">🎉 Systems Manager Instance Ready!</h1>
        <p class="info">This server is managed securely without SSH access.</p>
        <ul>
            <li>No inbound ports required</li>
            <li>No SSH keys needed</li>
            <li>Full audit logging enabled</li>
            <li>Managed through AWS Systems Manager</li>
        </ul>
        <p><strong>Hostname:</strong> $(hostname)</p>
        <p><strong>Instance ID:</strong> $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
        <p><strong>Last Updated:</strong> $(date)</p>
    </div>
</body>
</html>
HTMLCONTENT

%{else}
# Install and configure nginx on Ubuntu
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx

# Create custom index page
cat << 'HTMLCONTENT' > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
    <title>Systems Manager Managed Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
        .container { background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .success { color: #28a745; }
        .info { color: #17a2b8; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">🎉 Systems Manager Instance Ready!</h1>
        <p class="info">This server is managed securely without SSH access.</p>
        <ul>
            <li>No inbound ports required</li>
            <li>No SSH keys needed</li>
            <li>Full audit logging enabled</li>
            <li>Managed through AWS Systems Manager</li>
        </ul>
        <p><strong>Hostname:</strong> $(hostname)</p>
        <p><strong>Instance ID:</strong> $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
        <p><strong>Last Updated:</strong> $(date)</p>
    </div>
</body>
</html>
HTMLCONTENT
%{endif}

log_message "User data script completed successfully at $(date)"

# Signal completion to CloudFormation/Terraform if needed
echo "Instance configuration complete" > /tmp/setup-complete

EOF
}

# =========================================================================
# SYSTEMS MANAGER SESSION CONFIGURATION
# =========================================================================

# Configure Session Manager settings for enhanced logging and security
resource "aws_ssm_document" "session_manager_prefs" {
  count = var.enable_session_logging ? 1 : 0
  
  name          = "${local.name_prefix}-SessionManagerRunShell"
  document_type = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Document to hold regional settings for Session Manager"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = var.s3_bucket_name
      s3KeyPrefix                 = var.s3_key_prefix
      s3EncryptionEnabled         = var.s3_encryption_enabled
      cloudWatchLogGroupName      = var.enable_session_logging ? aws_cloudwatch_log_group.session_logs[0].name : ""
      cloudWatchEncryptionEnabled = var.cloudwatch_encryption_enabled
      kmsKeyId                    = var.kms_key_id
      runAsEnabled                = var.run_as_enabled
      runAsDefaultUser            = var.run_as_default_user
      idleSessionTimeout          = var.idle_session_timeout
      maxSessionDuration          = var.max_session_duration
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-session-manager-prefs"
    Type = "SSMDocument"
  })
}