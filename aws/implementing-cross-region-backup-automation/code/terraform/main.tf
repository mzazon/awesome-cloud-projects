# ==============================================================================
# Multi-Region Backup Strategies using AWS Backup
# ==============================================================================
# This Terraform configuration implements a comprehensive multi-region backup
# strategy using AWS Backup with cross-region copy destinations, EventBridge 
# for workflow automation, and lifecycle policies for cost optimization.
#
# Architecture includes:
# - Primary backup vault (us-east-1)
# - Secondary backup vault (us-west-2) 
# - Tertiary backup vault (eu-west-1)
# - Cross-region copy automation
# - EventBridge monitoring and alerting
# - Lambda-based backup validation
# ==============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# ==============================================================================
# Data Sources
# ==============================================================================

# Get current AWS account ID for ARN construction
data "aws_caller_identity" "current" {}

# Get available regions for multi-region deployment
data "aws_regions" "available" {}

# Get current region
data "aws_region" "current" {}

# ==============================================================================
# Local Values
# ==============================================================================

locals {
  # Account and region configuration
  account_id = data.aws_caller_identity.current.account_id
  primary_region = var.primary_region
  secondary_region = var.secondary_region
  tertiary_region = var.tertiary_region
  
  # Naming convention
  name_prefix = var.organization_name
  backup_plan_name = "${local.name_prefix}-multi-region-backup-plan"
  
  # Backup vault names
  primary_vault_name = "${local.name_prefix}-primary-vault"
  secondary_vault_name = "${local.name_prefix}-secondary-vault"
  tertiary_vault_name = "${local.name_prefix}-tertiary-vault"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Project     = "MultiRegionBackup"
    Environment = var.environment
    ManagedBy   = "Terraform"
    CreatedAt   = timestamp()
  })
}

# ==============================================================================
# Random Suffix for Unique Resource Names
# ==============================================================================

resource "random_id" "backup_suffix" {
  byte_length = 4
}

# ==============================================================================
# IAM Role for AWS Backup Service
# ==============================================================================

# Trust policy allowing AWS Backup service to assume the role
data "aws_iam_policy_document" "backup_service_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# Create the AWS Backup service role
resource "aws_iam_role" "backup_service_role" {
  name               = "${local.name_prefix}-backup-service-role"
  assume_role_policy = data.aws_iam_policy_document.backup_service_assume_role.json
  
  description = "Service role for AWS Backup to perform backup and restore operations"
  
  tags = local.common_tags
}

# Attach AWS managed policy for backup operations
resource "aws_iam_role_policy_attachment" "backup_service_backup_policy" {
  role       = aws_iam_role.backup_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# Attach AWS managed policy for restore operations
resource "aws_iam_role_policy_attachment" "backup_service_restore_policy" {
  role       = aws_iam_role.backup_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Attach AWS managed policy for S3 backup operations
resource "aws_iam_role_policy_attachment" "backup_service_s3_policy" {
  role       = aws_iam_role.backup_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForS3Backup"
}

# ==============================================================================
# KMS Keys for Backup Encryption (Multi-Region)
# ==============================================================================

# KMS key policy for backup encryption
data "aws_iam_policy_document" "backup_kms_key_policy" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
    
    actions   = ["kms:*"]
    resources = ["*"]
  }
  
  statement {
    sid    = "Allow AWS Backup Service"
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
    
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:ReEncrypt*",
      "kms:CreateGrant",
      "kms:DescribeKey"
    ]
    
    resources = ["*"]
  }
}

# Primary region KMS key for backup encryption
resource "aws_kms_key" "backup_key_primary" {
  description             = "KMS key for AWS Backup encryption in ${local.primary_region}"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  multi_region           = true
  
  policy = data.aws_iam_policy_document.backup_kms_key_policy.json
  
  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-backup-key-primary"
    Region = local.primary_region
  })
}

# KMS key alias for primary region
resource "aws_kms_alias" "backup_key_primary_alias" {
  name          = "alias/${local.name_prefix}-backup-key-primary"
  target_key_id = aws_kms_key.backup_key_primary.key_id
}

# ==============================================================================
# Backup Vaults (Multi-Region)
# ==============================================================================

# Primary backup vault in the main region
resource "aws_backup_vault" "primary" {
  name        = local.primary_vault_name
  kms_key_arn = aws_kms_key.backup_key_primary.arn
  
  tags = merge(local.common_tags, {
    Name   = local.primary_vault_name
    Region = local.primary_region
    Type   = "Primary"
  })
}

# Secondary backup vault for cross-region redundancy
resource "aws_backup_vault" "secondary" {
  provider = aws.secondary
  
  name        = local.secondary_vault_name
  kms_key_arn = "alias/aws/backup"  # Using AWS managed key for simplicity in secondary region
  
  tags = merge(local.common_tags, {
    Name   = local.secondary_vault_name
    Region = local.secondary_region
    Type   = "Secondary"
  })
}

# Tertiary backup vault for long-term archival
resource "aws_backup_vault" "tertiary" {
  provider = aws.tertiary
  
  name        = local.tertiary_vault_name
  kms_key_arn = "alias/aws/backup"  # Using AWS managed key for simplicity in tertiary region
  
  tags = merge(local.common_tags, {
    Name   = local.tertiary_vault_name
    Region = local.tertiary_region
    Type   = "Tertiary"
  })
}

# ==============================================================================
# Backup Plan with Cross-Region Copy Rules
# ==============================================================================

resource "aws_backup_plan" "multi_region" {
  name = local.backup_plan_name
  
  # Daily backups with cross-region copy to secondary region
  rule {
    rule_name         = "DailyBackupsWithCrossRegionCopy"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = var.daily_backup_schedule
    
    # Backup window configuration
    start_window      = var.backup_start_window
    completion_window = var.backup_completion_window
    
    # Lifecycle management for cost optimization
    lifecycle {
      cold_storage_after = var.daily_cold_storage_days
      delete_after      = var.daily_retention_days
    }
    
    # Cross-region copy to secondary region
    copy_action {
      destination_vault_arn = aws_backup_vault.secondary.arn
      
      lifecycle {
        cold_storage_after = var.daily_cold_storage_days
        delete_after      = var.daily_retention_days
      }
    }
    
    # Recovery point tags for organization and cost allocation
    recovery_point_tags = merge(local.common_tags, {
      BackupType    = "Daily"
      CrossRegion   = "true"
      Schedule      = "Automated"
      RetentionDays = tostring(var.daily_retention_days)
    })
  }
  
  # Weekly backups for long-term archival
  rule {
    rule_name         = "WeeklyLongTermArchival"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = var.weekly_backup_schedule
    
    # Backup window configuration
    start_window      = var.backup_start_window
    completion_window = var.backup_completion_window
    
    # Extended lifecycle for long-term retention
    lifecycle {
      cold_storage_after = var.weekly_cold_storage_days
      delete_after      = var.weekly_retention_days
    }
    
    # Cross-region copy to tertiary region for long-term archival
    copy_action {
      destination_vault_arn = aws_backup_vault.tertiary.arn
      
      lifecycle {
        cold_storage_after = var.weekly_cold_storage_days
        delete_after      = var.weekly_retention_days
      }
    }
    
    # Recovery point tags for long-term archival tracking
    recovery_point_tags = merge(local.common_tags, {
      BackupType    = "Weekly"
      LongTerm      = "true"
      Schedule      = "Automated"
      RetentionDays = tostring(var.weekly_retention_days)
    })
  }
  
  tags = local.common_tags
}

# ==============================================================================
# Backup Selection with Tag-Based Resource Discovery
# ==============================================================================

resource "aws_backup_selection" "production_resources" {
  iam_role_arn = aws_iam_role.backup_service_role.arn
  name         = "ProductionResourcesSelection"
  plan_id      = aws_backup_plan.multi_region.id
  
  # Use wildcard to include all resources that match tag conditions
  resources = ["*"]
  
  # Tag-based selection for automated resource discovery
  condition {
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.environment
    }
    
    string_equals {
      key   = "aws:ResourceTag/BackupEnabled"
      value = "true"
    }
  }
  
  # Additional condition to exclude test resources
  condition {
    string_not_like {
      key   = "aws:ResourceTag/Environment"
      value = "test*"
    }
  }
}

# ==============================================================================
# SNS Topic for Backup Notifications
# ==============================================================================

resource "aws_sns_topic" "backup_notifications" {
  name = "${local.name_prefix}-backup-notifications-${random_id.backup_suffix.hex}"
  
  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sns"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backup-notifications"
    Type = "Notifications"
  })
}

# SNS topic policy for EventBridge access
data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    
    actions = [
      "SNS:Publish"
    ]
    
    resources = [aws_sns_topic.backup_notifications.arn]
  }
  
  statement {
    sid    = "AllowLambdaPublish"
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.backup_validator_lambda_role.arn]
    }
    
    actions = [
      "SNS:Publish"
    ]
    
    resources = [aws_sns_topic.backup_notifications.arn]
  }
}

resource "aws_sns_topic_policy" "backup_notifications_policy" {
  arn    = aws_sns_topic.backup_notifications.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

# Email subscription for notifications (optional)
resource "aws_sns_topic_subscription" "email_notification" {
  count = var.notification_email != null ? 1 : 0
  
  topic_arn = aws_sns_topic.backup_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# Lambda Function for Backup Validation
# ==============================================================================

# IAM role for Lambda backup validator function
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "backup_validator_lambda_role" {
  name               = "${local.name_prefix}-backup-validator-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  
  tags = local.common_tags
}

# Lambda basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.backup_validator_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for backup validation operations
data "aws_iam_policy_document" "backup_validator_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "backup:DescribeBackupJob",
      "backup:ListCopyJobs",
      "backup:DescribeRecoveryPoint",
      "backup:ListRecoveryPoints",
      "backup:GetBackupPlan",
      "backup:GetBackupSelection"
    ]
    
    resources = ["*"]
  }
  
  statement {
    effect = "Allow"
    
    actions = [
      "sns:Publish"
    ]
    
    resources = [aws_sns_topic.backup_notifications.arn]
  }
  
  statement {
    effect = "Allow"
    
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    
    resources = ["arn:aws:logs:${local.primary_region}:${local.account_id}:*"]
  }
}

resource "aws_iam_role_policy" "backup_validator_policy" {
  name   = "${local.name_prefix}-backup-validator-policy"
  role   = aws_iam_role.backup_validator_lambda_role.id
  policy = data.aws_iam_policy_document.backup_validator_policy.json
}

# Lambda function code archive
data "archive_file" "backup_validator_zip" {
  type        = "zip"
  output_path = "${path.module}/backup_validator.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/backup_validator.py", {
      sns_topic_arn = aws_sns_topic.backup_notifications.arn
    })
    filename = "backup_validator.py"
  }
}

# Lambda function for backup validation
resource "aws_lambda_function" "backup_validator" {
  filename         = data.archive_file.backup_validator_zip.output_path
  function_name    = "${local.name_prefix}-backup-validator"
  role            = aws_iam_role.backup_validator_lambda_role.arn
  handler         = "backup_validator.lambda_handler"
  source_code_hash = data.archive_file.backup_validator_zip.output_base64sha256
  runtime         = "python3.12"
  timeout         = 300
  
  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.backup_notifications.arn
      LOG_LEVEL     = var.lambda_log_level
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backup-validator"
    Type = "BackupValidation"
  })
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "backup_validator_logs" {
  name              = "/aws/lambda/${aws_lambda_function.backup_validator.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# ==============================================================================
# EventBridge Rules for Backup Monitoring
# ==============================================================================

# EventBridge rule for backup job failures
resource "aws_cloudwatch_event_rule" "backup_job_failure" {
  name        = "${local.name_prefix}-backup-job-failure"
  description = "Capture backup job failures and aborted jobs"
  
  event_pattern = jsonencode({
    source       = ["aws.backup"]
    detail-type  = ["Backup Job State Change"]
    detail = {
      state = ["FAILED", "ABORTED"]
    }
  })
  
  tags = local.common_tags
}

# EventBridge rule for backup job completions
resource "aws_cloudwatch_event_rule" "backup_job_completed" {
  name        = "${local.name_prefix}-backup-job-completed"
  description = "Capture successful backup job completions"
  
  event_pattern = jsonencode({
    source       = ["aws.backup"]
    detail-type  = ["Backup Job State Change"]
    detail = {
      state = ["COMPLETED"]
    }
  })
  
  tags = local.common_tags
}

# EventBridge rule for copy job state changes
resource "aws_cloudwatch_event_rule" "copy_job_state_change" {
  name        = "${local.name_prefix}-copy-job-state-change"
  description = "Capture cross-region copy job state changes"
  
  event_pattern = jsonencode({
    source       = ["aws.backup"]
    detail-type  = ["Copy Job State Change"]
  })
  
  tags = local.common_tags
}

# ==============================================================================
# EventBridge Targets
# ==============================================================================

# Lambda target for backup job failures
resource "aws_cloudwatch_event_target" "backup_failure_lambda" {
  rule      = aws_cloudwatch_event_rule.backup_job_failure.name
  target_id = "BackupFailureLambdaTarget"
  arn       = aws_lambda_function.backup_validator.arn
}

# Lambda target for backup job completions
resource "aws_cloudwatch_event_target" "backup_completed_lambda" {
  rule      = aws_cloudwatch_event_rule.backup_job_completed.name
  target_id = "BackupCompletedLambdaTarget"
  arn       = aws_lambda_function.backup_validator.arn
}

# Lambda target for copy job state changes
resource "aws_cloudwatch_event_target" "copy_job_lambda" {
  rule      = aws_cloudwatch_event_rule.copy_job_state_change.name
  target_id = "CopyJobLambdaTarget"
  arn       = aws_lambda_function.backup_validator.arn
}

# SNS target for immediate failure notifications
resource "aws_cloudwatch_event_target" "backup_failure_sns" {
  rule      = aws_cloudwatch_event_rule.backup_job_failure.name
  target_id = "BackupFailureSNSTarget"
  arn       = aws_sns_topic.backup_notifications.arn
  
  input_transformer {
    input_paths = {
      account     = "$.account"
      region      = "$.region"
      time        = "$.time"
      backup_job  = "$.detail.backupJobId"
      state       = "$.detail.state"
      resource    = "$.detail.resourceArn"
    }
    
    input_template = jsonencode({
      "Alert": "AWS Backup Job Failed",
      "Account": "<account>",
      "Region": "<region>",
      "Time": "<time>",
      "BackupJobId": "<backup_job>",
      "State": "<state>",
      "ResourceArn": "<resource>",
      "Details": "A backup job has failed. Please check the AWS Backup console for more details."
    })
  }
}

# ==============================================================================
# Lambda Permissions for EventBridge
# ==============================================================================

resource "aws_lambda_permission" "allow_eventbridge_backup_failure" {
  statement_id  = "AllowExecutionFromEventBridgeBackupFailure"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_validator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.backup_job_failure.arn
}

resource "aws_lambda_permission" "allow_eventbridge_backup_completed" {
  statement_id  = "AllowExecutionFromEventBridgeBackupCompleted"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_validator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.backup_job_completed.arn
}

resource "aws_lambda_permission" "allow_eventbridge_copy_job" {
  statement_id  = "AllowExecutionFromEventBridgeCopyJob"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_validator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.copy_job_state_change.arn
}

# ==============================================================================
# CloudWatch Dashboard for Backup Monitoring
# ==============================================================================

resource "aws_cloudwatch_dashboard" "backup_monitoring" {
  dashboard_name = "${local.name_prefix}-backup-monitoring"
  
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
            ["AWS/Backup", "NumberOfBackupJobsCompleted", { "stat": "Sum" }],
            ["AWS/Backup", "NumberOfBackupJobsFailed", { "stat": "Sum" }],
            ["AWS/Backup", "NumberOfCopyJobsCompleted", { "stat": "Sum" }],
            ["AWS/Backup", "NumberOfCopyJobsFailed", { "stat": "Sum" }]
          ]
          period = 300
          stat   = "Sum"
          region = local.primary_region
          title  = "Backup Job Status"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        
        properties = {
          query   = "SOURCE '/aws/lambda/${aws_lambda_function.backup_validator.function_name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = local.primary_region
          title   = "Recent Backup Validation Logs"
        }
      }
    ]
  })
}