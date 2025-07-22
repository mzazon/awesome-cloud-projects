# main.tf - Main Terraform configuration for AWS Application Migration Service
# This file creates the complete infrastructure for large-scale server migration using AWS MGN

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and tagging
locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Resource naming
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Common tags applied to all resources
  common_tags = merge(
    var.additional_tags,
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Recipe      = "large-scale-server-migration-aws-application-migration-service"
    }
  )
  
  # MGN staging area tags
  staging_tags = merge(
    local.common_tags,
    var.staging_area_tags
  )
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# IAM role for AWS Application Migration Service
resource "aws_iam_role" "mgn_service_role" {
  name = "${local.name_prefix}-mgn-service-role-${random_string.suffix.result}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "mgn.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach the AWS managed policy for MGN service
resource "aws_iam_role_policy_attachment" "mgn_service_policy" {
  role       = aws_iam_role.mgn_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSApplicationMigrationServiceRolePolicy"
}

# IAM role for MGN replication servers (EC2 instances)
resource "aws_iam_role" "mgn_replication_server_role" {
  name = "${local.name_prefix}-mgn-replication-server-role-${random_string.suffix.result}"
  
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
  
  tags = local.common_tags
}

# IAM instance profile for replication servers
resource "aws_iam_instance_profile" "mgn_replication_server_profile" {
  name = "${local.name_prefix}-mgn-replication-server-profile-${random_string.suffix.result}"
  role = aws_iam_role.mgn_replication_server_role.name
  
  tags = local.common_tags
}

# Policy for replication servers to access MGN and CloudWatch
resource "aws_iam_role_policy" "mgn_replication_server_policy" {
  name = "${local.name_prefix}-mgn-replication-server-policy"
  role = aws_iam_role.mgn_replication_server_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "mgn:*",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ec2:ModifyInstanceAttribute",
          "ec2:RunInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:TerminateInstances",
          "ec2:CreateTags",
          "ec2:CreateSnapshot",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "iam:PassRole",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================

# Security group for MGN replication servers
resource "aws_security_group" "mgn_replication_servers" {
  name        = "${local.name_prefix}-mgn-replication-servers"
  description = "Security group for MGN replication servers"
  
  # Allow inbound traffic from source servers for replication
  ingress {
    from_port   = 1500
    to_port     = 1500
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    description = "MGN replication traffic from source servers"
  }
  
  # Allow outbound HTTPS traffic for AWS API calls
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound for AWS API calls"
  }
  
  # Allow outbound HTTP traffic for package updates
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP outbound for package updates"
  }
  
  # Allow all outbound traffic to VPC for internal communication
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    description = "All outbound traffic within VPC"
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-mgn-replication-servers"
    }
  )
}

# Security group for migrated instances
resource "aws_security_group" "mgn_migrated_instances" {
  name        = "${local.name_prefix}-mgn-migrated-instances"
  description = "Security group for MGN migrated instances"
  
  # Allow SSH access (modify as needed for your requirements)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "SSH access from private networks"
  }
  
  # Allow RDP access for Windows servers
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "RDP access for Windows servers"
  }
  
  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-mgn-migrated-instances"
    }
  )
}

# =============================================================================
# CLOUDWATCH RESOURCES
# =============================================================================

# CloudWatch Log Group for MGN operations
resource "aws_cloudwatch_log_group" "mgn_operations" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  name              = "/aws/mgn/${local.name_prefix}"
  retention_in_days = 30
  
  kms_key_id = var.kms_key_id != "" ? var.kms_key_id : null
  
  tags = local.common_tags
}

# CloudWatch metric alarm for replication lag
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-mgn-replication-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicationLag"
  namespace           = "AWS/MGN"
  period              = "300"
  statistic           = "Average"
  threshold           = "300"
  alarm_description   = "This metric monitors MGN replication lag"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  
  tags = local.common_tags
}

# =============================================================================
# S3 RESOURCES
# =============================================================================

# S3 bucket for MGN logs and artifacts
resource "aws_s3_bucket" "mgn_logs" {
  bucket = "${local.name_prefix}-mgn-logs-${random_string.suffix.result}"
  
  tags = local.common_tags
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "mgn_logs" {
  bucket = aws_s3_bucket.mgn_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "mgn_logs" {
  bucket = aws_s3_bucket.mgn_logs.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_id != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id != "" ? var.kms_key_id : null
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "mgn_logs" {
  bucket = aws_s3_bucket.mgn_logs.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# MGN REPLICATION CONFIGURATION TEMPLATE
# =============================================================================

# MGN replication configuration template
resource "aws_mgn_replication_configuration_template" "main" {
  associate_default_security_group = var.mgn_associate_default_security_group
  bandwidth_throttling             = var.mgn_bandwidth_throttling
  create_public_ip                 = var.mgn_create_public_ip
  data_plane_routing              = var.mgn_data_plane_routing
  default_large_staging_disk_type = var.mgn_staging_disk_type
  ebs_encryption                  = var.mgn_ebs_encryption
  ebs_encryption_key_arn          = var.kms_key_id != "" ? var.kms_key_id : null
  replication_server_instance_type = var.mgn_replication_server_instance_type
  
  # Use provided security groups or default
  replication_servers_security_groups_ids = length(var.replication_security_group_ids) > 0 ? var.replication_security_group_ids : [aws_security_group.mgn_replication_servers.id]
  
  # Use provided subnet or let MGN choose
  staging_area_subnet_id = var.staging_subnet_id != "" ? var.staging_subnet_id : null
  
  staging_area_tags = local.staging_tags
  
  use_dedicated_replication_server = var.mgn_use_dedicated_replication_server
  
  tags = local.common_tags
}

# =============================================================================
# MIGRATION WAVES
# =============================================================================

# Create migration waves for organized server migration
resource "aws_mgn_wave" "migration_waves" {
  count = length(var.migration_waves)
  
  name        = var.migration_waves[count.index].name
  description = var.migration_waves[count.index].description
  
  tags = merge(
    local.common_tags,
    {
      Name = var.migration_waves[count.index].name
      Wave = count.index + 1
    }
  )
}

# =============================================================================
# LAUNCH CONFIGURATION TEMPLATE
# =============================================================================

# Launch template for post-launch actions
resource "aws_launch_template" "mgn_post_launch" {
  name_prefix   = "${local.name_prefix}-mgn-post-launch-"
  description   = "Launch template for MGN post-launch actions"
  
  # Basic instance configuration
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  
  # IAM instance profile for post-launch actions
  iam_instance_profile {
    name = aws_iam_instance_profile.mgn_replication_server_profile.name
  }
  
  # Security group for post-launch actions
  vpc_security_group_ids = [aws_security_group.mgn_migrated_instances.id]
  
  # User data for post-launch actions
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    cloudwatch_log_group = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mgn_operations[0].name : ""
    s3_bucket           = aws_s3_bucket.mgn_logs.bucket
    s3_prefix           = var.s3_output_key_prefix
  }))
  
  # Block device mappings
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_id != "" ? var.kms_key_id : null
      delete_on_termination = true
    }
  }
  
  # Enable detailed monitoring
  monitoring {
    enabled = var.enable_cloudwatch_monitoring
  }
  
  # Tags
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.name_prefix}-mgn-post-launch-instance"
      }
    )
  }
  
  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.name_prefix}-mgn-post-launch-volume"
      }
    )
  }
  
  tags = local.common_tags
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# USER DATA SCRIPT FOR POST-LAUNCH ACTIONS
# =============================================================================

# Create user data script for post-launch actions
resource "local_file" "user_data_script" {
  content = templatefile("${path.module}/templates/user_data.sh.tpl", {
    cloudwatch_log_group = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mgn_operations[0].name : ""
    s3_bucket           = aws_s3_bucket.mgn_logs.bucket
    s3_prefix           = var.s3_output_key_prefix
    region              = local.region
  })
  filename = "${path.module}/user_data.sh"
}

# =============================================================================
# OUTPUTS FOR EXTERNAL INTEGRATIONS
# =============================================================================

# Output the replication configuration template ID
output "mgn_replication_template_id" {
  description = "ID of the MGN replication configuration template"
  value       = aws_mgn_replication_configuration_template.main.replication_configuration_template_id
}

# Output migration wave IDs
output "migration_wave_ids" {
  description = "IDs of created migration waves"
  value       = aws_mgn_wave.migration_waves[*].wave_id
}

# Output security group IDs
output "security_group_ids" {
  description = "Security group IDs for MGN infrastructure"
  value = {
    replication_servers = aws_security_group.mgn_replication_servers.id
    migrated_instances  = aws_security_group.mgn_migrated_instances.id
  }
}

# Output S3 bucket information
output "s3_bucket_info" {
  description = "S3 bucket information for MGN logs"
  value = {
    bucket_name = aws_s3_bucket.mgn_logs.bucket
    bucket_arn  = aws_s3_bucket.mgn_logs.arn
  }
}

# Output CloudWatch log group (if enabled)
output "cloudwatch_log_group" {
  description = "CloudWatch log group for MGN operations"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mgn_operations[0].name : null
}

# Output IAM role ARNs
output "iam_role_arns" {
  description = "IAM role ARNs for MGN service and replication servers"
  value = {
    service_role            = aws_iam_role.mgn_service_role.arn
    replication_server_role = aws_iam_role.mgn_replication_server_role.arn
  }
}

# Output launch template information
output "launch_template_info" {
  description = "Launch template information for post-launch actions"
  value = {
    id               = aws_launch_template.mgn_post_launch.id
    latest_version   = aws_launch_template.mgn_post_launch.latest_version
    name             = aws_launch_template.mgn_post_launch.name
  }
}