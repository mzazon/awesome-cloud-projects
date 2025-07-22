# Main Terraform Configuration for Automated Patching Infrastructure
# This file creates all the resources needed for automated patch management using AWS Systems Manager

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  # Generate unique resource names with prefix or random suffix
  name_prefix = var.resource_name_prefix != "" ? var.resource_name_prefix : "patch-mgmt-${random_string.suffix.result}"
  
  # S3 bucket name for patch logs
  s3_bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "patch-reports-${data.aws_caller_identity.current.account_id}-${random_string.suffix.result}"
  
  # Common tags for all resources
  common_tags = {
    Project     = "Automated Patching"
    Environment = var.environment
    PatchGroup  = var.patch_group
    Recipe      = "automated-patching-maintenance-windows-systems-manager"
    ManagedBy   = "Terraform"
  }
}

# ==============================================================================
# S3 BUCKET FOR PATCH LOGS AND REPORTS
# ==============================================================================

# S3 bucket for storing patch logs and compliance reports
resource "aws_s3_bucket" "patch_logs" {
  bucket = local.s3_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-logs"
    Type = "PatchLogs"
  })
}

# Configure S3 bucket versioning for log retention
resource "aws_s3_bucket_versioning" "patch_logs" {
  bucket = aws_s3_bucket.patch_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "patch_logs" {
  bucket = aws_s3_bucket.patch_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "patch_logs" {
  bucket = aws_s3_bucket.patch_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for log retention
resource "aws_s3_bucket_lifecycle_configuration" "patch_logs" {
  bucket = aws_s3_bucket.patch_logs.id

  rule {
    id     = "patch_logs_lifecycle"
    status = "Enabled"

    # Transition to IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete after 365 days
    expiration {
      days = 365
    }

    # Delete incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ==============================================================================
# IAM ROLE FOR MAINTENANCE WINDOW OPERATIONS
# ==============================================================================

# Trust policy for Systems Manager service
data "aws_iam_policy_document" "maintenance_window_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

# IAM role for maintenance window operations
resource "aws_iam_role" "maintenance_window" {
  name               = "${local.name_prefix}-maintenance-window-role"
  assume_role_policy = data.aws_iam_policy_document.maintenance_window_trust.json
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-maintenance-window-role"
    Type = "ServiceRole"
  })
}

# Attach the AWS managed policy for maintenance window operations
resource "aws_iam_role_policy_attachment" "maintenance_window" {
  role       = aws_iam_role.maintenance_window.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
}

# Custom IAM policy for S3 access
data "aws_iam_policy_document" "s3_access" {
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    
    resources = [
      aws_s3_bucket.patch_logs.arn,
      "${aws_s3_bucket.patch_logs.arn}/*"
    ]
  }
}

# Attach S3 access policy to maintenance window role
resource "aws_iam_role_policy" "s3_access" {
  name   = "${local.name_prefix}-s3-access"
  role   = aws_iam_role.maintenance_window.id
  policy = data.aws_iam_policy_document.s3_access.json
}

# ==============================================================================
# CUSTOM PATCH BASELINE
# ==============================================================================

# Custom patch baseline for controlled patch deployment
resource "aws_ssm_patch_baseline" "custom" {
  name             = "${local.name_prefix}-baseline"
  description      = "Custom patch baseline for ${var.environment} environment"
  operating_system = var.patch_baseline_operating_system
  
  # Define patch approval rules
  approval_rule {
    approve_after_days  = var.patch_approve_after_days
    compliance_level    = var.patch_compliance_level
    enable_non_security = true
    
    # Patch filter for classifications
    patch_filter {
      key    = "CLASSIFICATION"
      values = var.patch_classification_filters
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-baseline"
    Type = "PatchBaseline"
  })
}

# Associate patch baseline with patch group
resource "aws_ssm_patch_group" "main" {
  baseline_id = aws_ssm_patch_baseline.custom.id
  patch_group = var.patch_group
}

# ==============================================================================
# MAINTENANCE WINDOW FOR PATCH INSTALLATION
# ==============================================================================

# Maintenance window for patch installation
resource "aws_ssm_maintenance_window" "patch_installation" {
  name                       = "${local.name_prefix}-patch-window"
  description                = "Weekly patching maintenance window for ${var.environment}"
  schedule                   = var.maintenance_window_schedule
  duration                   = var.maintenance_window_duration
  cutoff                     = var.maintenance_window_cutoff
  schedule_timezone          = "UTC"
  allow_unassociated_targets = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-patch-window"
    Type = "MaintenanceWindow"
  })
}

# Register EC2 instances as targets based on tags
resource "aws_ssm_maintenance_window_target" "patch_targets" {
  window_id     = aws_ssm_maintenance_window.patch_installation.id
  name          = "${local.name_prefix}-patch-targets"
  description   = "EC2 instances targeted for patching"
  resource_type = "INSTANCE"
  
  targets {
    key    = "tag:${var.target_tag_key}"
    values = [var.target_tag_value]
  }
}

# Register patch installation task
resource "aws_ssm_maintenance_window_task" "patch_installation" {
  window_id        = aws_ssm_maintenance_window.patch_installation.id
  name             = "${local.name_prefix}-patch-task"
  description      = "Install patches using custom baseline"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.maintenance_window.arn
  max_concurrency  = var.max_concurrency
  max_errors       = var.max_errors
  
  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.patch_targets.id]
  }
  
  task_invocation_parameters {
    run_command_parameters {
      # Override default patch baseline with custom one
      parameter {
        name   = "BaselineOverride"
        values = [aws_ssm_patch_baseline.custom.id]
      }
      
      # Set operation to Install
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
      
      # Configure CloudWatch logging
      cloudwatch_config {
        cloudwatch_log_group_name = aws_cloudwatch_log_group.patch_logs.name
        cloudwatch_output_enabled = true
      }
      
      # Configure S3 logging
      s3_config {
        s3_bucket_name = aws_s3_bucket.patch_logs.id
        s3_key_prefix  = "patch-logs/"
      }
    }
  }
}

# ==============================================================================
# MAINTENANCE WINDOW FOR PATCH SCANNING
# ==============================================================================

# Maintenance window for daily patch scanning
resource "aws_ssm_maintenance_window" "patch_scanning" {
  name                       = "${local.name_prefix}-scan-window"
  description                = "Daily patch scanning maintenance window"
  schedule                   = var.scan_window_schedule
  duration                   = var.scan_window_duration
  cutoff                     = 1
  schedule_timezone          = "UTC"
  allow_unassociated_targets = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-scan-window"
    Type = "ScanWindow"
  })
}

# Register EC2 instances as scan targets
resource "aws_ssm_maintenance_window_target" "scan_targets" {
  window_id     = aws_ssm_maintenance_window.patch_scanning.id
  name          = "${local.name_prefix}-scan-targets"
  description   = "EC2 instances targeted for scanning"
  resource_type = "INSTANCE"
  
  targets {
    key    = "tag:${var.target_tag_key}"
    values = [var.target_tag_value]
  }
}

# Register patch scanning task
resource "aws_ssm_maintenance_window_task" "patch_scanning" {
  window_id        = aws_ssm_maintenance_window.patch_scanning.id
  name             = "${local.name_prefix}-scan-task"
  description      = "Scan for missing patches"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.maintenance_window.arn
  max_concurrency  = var.scan_max_concurrency
  max_errors       = var.scan_max_errors
  
  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.scan_targets.id]
  }
  
  task_invocation_parameters {
    run_command_parameters {
      # Override default patch baseline with custom one
      parameter {
        name   = "BaselineOverride"
        values = [aws_ssm_patch_baseline.custom.id]
      }
      
      # Set operation to Scan
      parameter {
        name   = "Operation"
        values = ["Scan"]
      }
      
      # Configure CloudWatch logging
      cloudwatch_config {
        cloudwatch_log_group_name = aws_cloudwatch_log_group.patch_logs.name
        cloudwatch_output_enabled = true
      }
      
      # Configure S3 logging
      s3_config {
        s3_bucket_name = aws_s3_bucket.patch_logs.id
        s3_key_prefix  = "scan-logs/"
      }
    }
  }
}

# ==============================================================================
# CLOUDWATCH MONITORING AND NOTIFICATIONS
# ==============================================================================

# CloudWatch log group for patch operations
resource "aws_cloudwatch_log_group" "patch_logs" {
  name              = "/aws/ssm/${local.name_prefix}-patch-logs"
  retention_in_days = 30
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-patch-logs"
    Type = "LogGroup"
  })
}

# SNS topic for patch notifications
resource "aws_sns_topic" "patch_notifications" {
  name = "${local.name_prefix}-notifications"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-notifications"
    Type = "SNSTopic"
  })
}

# SNS topic policy for CloudWatch alarms
data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    
    actions = ["SNS:Publish"]
    
    resources = [aws_sns_topic.patch_notifications.arn]
  }
}

# Apply policy to SNS topic
resource "aws_sns_topic_policy" "patch_notifications" {
  arn    = aws_sns_topic.patch_notifications.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

# SNS topic subscription for email notifications (only if email is provided)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.patch_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarm for patch compliance monitoring
resource "aws_cloudwatch_metric_alarm" "patch_compliance" {
  count               = var.enable_patch_compliance_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-patch-compliance"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ComplianceByPatchGroup"
  namespace           = "AWS/SSM-PatchCompliance"
  period              = "3600"
  statistic           = "Maximum"
  threshold           = "1"
  alarm_description   = "This metric monitors patch compliance status"
  alarm_actions       = [aws_sns_topic.patch_notifications.arn]
  
  dimensions = {
    PatchGroup = var.patch_group
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-patch-compliance"
    Type = "CloudWatchAlarm"
  })
}

# ==============================================================================
# ADDITIONAL MONITORING RESOURCES
# ==============================================================================

# CloudWatch dashboard for patch management overview
resource "aws_cloudwatch_dashboard" "patch_management" {
  dashboard_name = "${local.name_prefix}-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/SSM-PatchCompliance", "ComplianceByPatchGroup", "PatchGroup", var.patch_group],
            ["AWS/SSM-PatchCompliance", "NonCompliantInstanceCount", "PatchGroup", var.patch_group],
            ["AWS/SSM-PatchCompliance", "CompliantInstanceCount", "PatchGroup", var.patch_group]
          ]
          period = 300
          stat   = "Maximum"
          region = data.aws_region.current.name
          title  = "Patch Compliance Overview"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          query = "SOURCE '${aws_cloudwatch_log_group.patch_logs.name}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 50"
          region = data.aws_region.current.name
          title  = "Recent Patch Errors"
        }
      }
    ]
  })
}