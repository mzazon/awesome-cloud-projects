# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  # Generate unique names for resources
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_string.suffix.result
  
  # Resource names
  vpc_name                = "${local.name_prefix}-vpc-${local.name_suffix}"
  efs_name               = "${local.name_prefix}-efs-${local.name_suffix}"
  datasync_task_name     = var.datasync_task_name != "" ? var.datasync_task_name : "${local.name_prefix}-task-${local.name_suffix}"
  source_bucket_name     = var.source_bucket_name != "" ? var.source_bucket_name : "${local.name_prefix}-source-${local.name_suffix}"
  
  # Select availability zone
  selected_az = var.availability_zone != "" ? var.availability_zone : data.aws_availability_zones.available.names[0]
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    CreatedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# VPC Infrastructure
# -----------------------------------------------------------------------------

# Create VPC for EFS and DataSync resources
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = local.vpc_name
  })
}

# Create private subnet for EFS mount targets
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = local.selected_az

  tags = merge(local.common_tags, {
    Name = "${local.vpc_name}-private"
    Type = "Private"
  })
}

# Create route table for private subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.vpc_name}-private-rt"
  })
}

# Associate route table with private subnet
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Security group for EFS access
resource "aws_security_group" "efs" {
  name        = "${local.vpc_name}-efs-sg"
  description = "Security group for EFS access from DataSync"
  vpc_id      = aws_vpc.main.id

  # Allow NFS traffic (port 2049) within VPC
  ingress {
    description = "NFS access from VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.vpc_name}-efs-sg"
  })
}

# -----------------------------------------------------------------------------
# Amazon EFS Configuration
# -----------------------------------------------------------------------------

# Create EFS file system
resource "aws_efs_file_system" "main" {
  creation_token   = local.efs_name
  performance_mode = var.efs_performance_mode
  throughput_mode  = var.efs_throughput_mode
  encrypted        = var.efs_encrypted

  # Set provisioned throughput only if throughput mode is provisioned
  provisioned_throughput_in_mibps = var.efs_throughput_mode == "provisioned" ? var.efs_provisioned_throughput : null

  # Lifecycle policy for Infrequent Access
  dynamic "lifecycle_policy" {
    for_each = var.efs_transition_to_ia != "" ? [1] : []
    content {
      transition_to_ia = var.efs_transition_to_ia
    }
  }

  tags = merge(local.common_tags, {
    Name = local.efs_name
  })
}

# Create EFS mount target in private subnet
resource "aws_efs_mount_target" "main" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.efs.id]
}

# -----------------------------------------------------------------------------
# S3 Source Bucket Configuration
# -----------------------------------------------------------------------------

# Create S3 bucket for source data (if enabled)
resource "aws_s3_bucket" "source" {
  count  = var.create_source_bucket ? 1 : 0
  bucket = local.source_bucket_name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-source-bucket"
    Type = "DataSync Source"
  })
}

# Configure S3 bucket versioning
resource "aws_s3_bucket_versioning" "source" {
  count  = var.create_source_bucket ? 1 : 0
  bucket = aws_s3_bucket.source[0].id
  
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# Configure S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  count  = var.create_source_bucket ? 1 : 0
  bucket = aws_s3_bucket.source[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "source" {
  count  = var.create_source_bucket ? 1 : 0
  bucket = aws_s3_bucket.source[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create sample data files in S3 bucket (if enabled)
resource "aws_s3_object" "sample_files" {
  count = var.create_source_bucket && var.create_sample_data ? length(var.sample_data_files) : 0
  
  bucket        = aws_s3_bucket.source[0].id
  key           = var.sample_data_files[count.index].key
  content       = var.sample_data_files[count.index].content
  storage_class = var.s3_storage_class

  tags = merge(local.common_tags, {
    Name = "Sample file ${count.index + 1}"
    Type = "Test Data"
  })
}

# -----------------------------------------------------------------------------
# IAM Role for DataSync
# -----------------------------------------------------------------------------

# Trust policy for DataSync service
data "aws_iam_policy_document" "datasync_trust" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["datasync.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for DataSync
resource "aws_iam_role" "datasync" {
  name               = "${local.name_prefix}-datasync-role-${local.name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.datasync_trust.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-datasync-role"
  })
}

# Attach AWS managed policy for S3 read access
resource "aws_iam_role_policy_attachment" "datasync_s3" {
  role       = aws_iam_role.datasync.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# Custom policy for EFS and CloudWatch access
data "aws_iam_policy_document" "datasync_custom" {
  # EFS permissions
  statement {
    effect = "Allow"
    actions = [
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets",
      "elasticfilesystem:DescribeAccessPoints",
    ]
    resources = ["*"]
  }

  # CloudWatch Logs permissions (if enabled)
  dynamic "statement" {
    for_each = var.enable_cloudwatch_logs ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/datasync/*"]
    }
  }
}

# Attach custom policy to DataSync role
resource "aws_iam_role_policy" "datasync_custom" {
  name   = "${local.name_prefix}-datasync-custom-policy"
  role   = aws_iam_role.datasync.id
  policy = data.aws_iam_policy_document.datasync_custom.json
}

# -----------------------------------------------------------------------------
# CloudWatch Logs Configuration
# -----------------------------------------------------------------------------

# CloudWatch Log Group for DataSync (if enabled)
resource "aws_cloudwatch_log_group" "datasync" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/datasync/${local.datasync_task_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-datasync-logs"
  })
}

# -----------------------------------------------------------------------------
# SNS Notification Configuration
# -----------------------------------------------------------------------------

# SNS topic for DataSync notifications (if enabled)
resource "aws_sns_topic" "datasync_notifications" {
  count = var.enable_sns_notifications ? 1 : 0
  name  = "${local.name_prefix}-datasync-notifications"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-datasync-notifications"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email" {
  count     = var.enable_sns_notifications ? 1 : 0
  topic_arn = aws_sns_topic.datasync_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# -----------------------------------------------------------------------------
# DataSync Locations Configuration
# -----------------------------------------------------------------------------

# DataSync S3 location
resource "aws_datasync_location_s3" "source" {
  s3_bucket_arn = var.create_source_bucket ? aws_s3_bucket.source[0].arn : "arn:aws:s3:::${local.source_bucket_name}"
  subdirectory  = "/"

  s3_config {
    bucket_access_role_arn = aws_iam_role.datasync.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-location"
    Type = "Source"
  })

  depends_on = [
    aws_iam_role_policy_attachment.datasync_s3,
    aws_iam_role_policy.datasync_custom
  ]
}

# DataSync EFS location
resource "aws_datasync_location_efs" "target" {
  efs_file_system_arn = aws_efs_file_system.main.arn
  subdirectory        = "/"

  ec2_config {
    security_group_arns = [aws_security_group.efs.arn]
    subnet_arn         = aws_subnet.private.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-efs-location"
    Type = "Target"
  })

  depends_on = [aws_efs_mount_target.main]
}

# -----------------------------------------------------------------------------
# DataSync Task Configuration
# -----------------------------------------------------------------------------

# DataSync task for S3 to EFS synchronization
resource "aws_datasync_task" "main" {
  destination_location_arn = aws_datasync_location_efs.target.arn
  name                    = local.datasync_task_name
  source_location_arn     = aws_datasync_location_s3.source.arn

  # Configure DataSync options
  options {
    verify_mode                = var.datasync_verify_mode
    overwrite_mode            = var.datasync_overwrite_mode
    atime                     = "BEST_EFFORT"
    mtime                     = "PRESERVE"
    uid                       = "INT_VALUE"
    gid                       = "INT_VALUE"
    preserve_deleted_files    = var.datasync_preserve_deleted_files
    preserve_devices          = "NONE"
    posix_permissions         = "PRESERVE"
    bytes_per_second         = var.datasync_bandwidth_limit
    task_queueing            = "ENABLED"
    log_level                = var.datasync_log_level

    # Configure CloudWatch Logs destination (if enabled)
    dynamic "cloud_watch_log_group_arn" {
      for_each = var.enable_cloudwatch_logs ? [aws_cloudwatch_log_group.datasync[0].arn] : []
      content {
        cloud_watch_log_group_arn = cloud_watch_log_group_arn.value
      }
    }
  }

  # Include/exclude patterns can be added here if needed
  # includes {
  #   filter_type = "SIMPLE_PATTERN"
  #   value       = "*.txt"
  # }

  tags = merge(local.common_tags, {
    Name = local.datasync_task_name
    Type = "Synchronization Task"
  })

  depends_on = [
    aws_datasync_location_s3.source,
    aws_datasync_location_efs.target
  ]
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms for Monitoring
# -----------------------------------------------------------------------------

# CloudWatch alarm for DataSync task failures (if SNS is enabled)
resource "aws_cloudwatch_metric_alarm" "datasync_task_failure" {
  count = var.enable_sns_notifications ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-datasync-task-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "TaskExecutionsFailed"
  namespace           = "AWS/DataSync"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors DataSync task execution failures"
  alarm_actions       = [aws_sns_topic.datasync_notifications[0].arn]

  dimensions = {
    TaskArn = aws_datasync_task.main.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-datasync-failure-alarm"
  })
}