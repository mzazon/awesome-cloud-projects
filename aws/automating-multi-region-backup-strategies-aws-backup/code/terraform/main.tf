# Multi-Region AWS Backup Strategy Infrastructure
# This Terraform configuration implements automated backup strategies across
# multiple AWS regions with cross-region replication, lifecycle management,
# and comprehensive monitoring capabilities

# Data sources for current AWS account and caller identity
data "aws_caller_identity" "current" {
  provider = aws.primary
}

data "aws_region" "primary" {
  provider = aws.primary
}

data "aws_region" "secondary" {
  provider = aws.secondary
}

data "aws_region" "tertiary" {
  provider = aws.tertiary
}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  resource_prefix = "${var.organization_name}-${var.environment}"
  common_tags = {
    Project       = "Multi-Region Backup Strategy"
    Environment   = var.environment
    Organization  = var.organization_name
    BackupEnabled = "self"
  }
}

# ========================================
# KMS Keys for Backup Encryption
# ========================================

# KMS key for backup encryption in primary region
resource "aws_kms_key" "backup_primary" {
  provider                = aws.primary
  description             = "KMS key for AWS Backup encryption in ${var.primary_region}"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow AWS Backup"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name   = "${local.resource_prefix}-backup-key-primary"
    Region = var.primary_region
  })
}

resource "aws_kms_alias" "backup_primary" {
  provider      = aws.primary
  name          = "alias/${local.resource_prefix}-backup-key-primary"
  target_key_id = aws_kms_key.backup_primary.key_id
}

# KMS key for backup encryption in secondary region
resource "aws_kms_key" "backup_secondary" {
  provider                = aws.secondary
  description             = "KMS key for AWS Backup encryption in ${var.secondary_region}"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow AWS Backup"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name   = "${local.resource_prefix}-backup-key-secondary"
    Region = var.secondary_region
  })
}

resource "aws_kms_alias" "backup_secondary" {
  provider      = aws.secondary
  name          = "alias/${local.resource_prefix}-backup-key-secondary"
  target_key_id = aws_kms_key.backup_secondary.key_id
}

# KMS key for backup encryption in tertiary region
resource "aws_kms_key" "backup_tertiary" {
  provider                = aws.tertiary
  description             = "KMS key for AWS Backup encryption in ${var.tertiary_region}"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow AWS Backup"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name   = "${local.resource_prefix}-backup-key-tertiary"
    Region = var.tertiary_region
  })
}

resource "aws_kms_alias" "backup_tertiary" {
  provider      = aws.tertiary
  name          = "alias/${local.resource_prefix}-backup-key-tertiary"
  target_key_id = aws_kms_key.backup_tertiary.key_id
}

# ========================================
# IAM Roles and Policies for AWS Backup
# ========================================

# IAM assume role policy document for AWS Backup service
data "aws_iam_policy_document" "backup_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for AWS Backup service operations
resource "aws_iam_role" "backup_service_role" {
  provider           = aws.primary
  name               = "${local.resource_prefix}-backup-service-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-backup-service-role"
  })
}

# Attach AWS managed policies for backup operations
resource "aws_iam_role_policy_attachment" "backup_service_role_policy" {
  provider   = aws.primary
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.backup_service_role.name
}

resource "aws_iam_role_policy_attachment" "backup_service_role_s3_policy" {
  provider   = aws.primary
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
  role       = aws_iam_role.backup_service_role.name
}

resource "aws_iam_role_policy_attachment" "backup_service_role_restores_policy" {
  provider   = aws.primary
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
  role       = aws_iam_role.backup_service_role.name
}

# Custom IAM policy for cross-region backup operations
data "aws_iam_policy_document" "cross_region_backup_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "backup:CopyIntoBackupVault",
      "backup:CreateBackupSelection",
      "backup:DeleteBackupSelection",
      "backup:GetBackupPlan",
      "backup:GetBackupSelection",
      "backup:ListBackupJobs",
      "backup:ListBackupSelections",
      "backup:ListRecoveryPoints",
      "backup:StartCopyJob",
      "backup:DescribeBackupJob",
      "backup:DescribeCopyJob"
    ]
    
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:ReEncrypt*"
    ]
    
    resources = [
      aws_kms_key.backup_primary.arn,
      aws_kms_key.backup_secondary.arn,
      aws_kms_key.backup_tertiary.arn
    ]
  }
}

resource "aws_iam_role_policy" "cross_region_backup_policy" {
  provider = aws.primary
  name     = "${local.resource_prefix}-cross-region-backup-policy"
  role     = aws_iam_role.backup_service_role.id
  policy   = data.aws_iam_policy_document.cross_region_backup_policy.json
}

# ========================================
# AWS Backup Vaults
# ========================================

# Primary backup vault
resource "aws_backup_vault" "primary" {
  provider    = aws.primary
  name        = "${local.resource_prefix}-primary-vault"
  kms_key_arn = var.enable_backup_encryption ? aws_kms_key.backup_primary.arn : null
  
  tags = merge(local.common_tags, {
    Name   = "${local.resource_prefix}-primary-vault"
    Region = var.primary_region
    Type   = "primary"
  })
}

# Secondary backup vault for disaster recovery
resource "aws_backup_vault" "secondary" {
  provider    = aws.secondary
  name        = "${local.resource_prefix}-secondary-vault"
  kms_key_arn = var.enable_backup_encryption ? aws_kms_key.backup_secondary.arn : null
  
  tags = merge(local.common_tags, {
    Name   = "${local.resource_prefix}-secondary-vault"
    Region = var.secondary_region
    Type   = "secondary"
  })
}

# Tertiary backup vault for long-term archival
resource "aws_backup_vault" "tertiary" {
  provider    = aws.tertiary
  name        = "${local.resource_prefix}-tertiary-vault"
  kms_key_arn = var.enable_backup_encryption ? aws_kms_key.backup_tertiary.arn : null
  
  tags = merge(local.common_tags, {
    Name   = "${local.resource_prefix}-tertiary-vault"
    Region = var.tertiary_region
    Type   = "tertiary"
  })
}

# Optional: Backup vault lock for compliance (when enabled)
resource "aws_backup_vault_lock_configuration" "primary" {
  count                   = var.enable_backup_vault_lock ? 1 : 0
  provider                = aws.primary
  backup_vault_name       = aws_backup_vault.primary.name
  min_retention_days      = var.backup_vault_lock_min_retention_days
  changeable_for_days     = 3
}

# ========================================
# SNS Topic and Notifications
# ========================================

# SNS topic for backup notifications
resource "aws_sns_topic" "backup_notifications" {
  count    = var.enable_sns_notifications ? 1 : 0
  provider = aws.primary
  name     = "${local.resource_prefix}-backup-notifications"
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-backup-notifications"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "backup_email_notifications" {
  count     = var.enable_sns_notifications ? 1 : 0
  provider  = aws.primary
  topic_arn = aws_sns_topic.backup_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM policy document for SNS topic
data "aws_iam_policy_document" "backup_sns_policy" {
  count = var.enable_sns_notifications ? 1 : 0
  
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
    
    actions = ["SNS:Publish"]
    
    resources = [aws_sns_topic.backup_notifications[0].arn]
  }
}

resource "aws_sns_topic_policy" "backup_notifications" {
  count    = var.enable_sns_notifications ? 1 : 0
  provider = aws.primary
  arn      = aws_sns_topic.backup_notifications[0].arn
  policy   = data.aws_iam_policy_document.backup_sns_policy[0].json
}

# Backup vault notifications
resource "aws_backup_vault_notifications" "primary" {
  count             = var.enable_sns_notifications ? 1 : 0
  provider          = aws.primary
  backup_vault_name = aws_backup_vault.primary.name
  sns_topic_arn     = aws_sns_topic.backup_notifications[0].arn
  
  backup_vault_events = [
    "BACKUP_JOB_STARTED",
    "BACKUP_JOB_COMPLETED",
    "BACKUP_JOB_SUCCESSFUL",
    "BACKUP_JOB_FAILED",
    "BACKUP_JOB_EXPIRED",
    "RESTORE_JOB_STARTED",
    "RESTORE_JOB_COMPLETED",
    "COPY_JOB_STARTED",
    "COPY_JOB_SUCCESSFUL",
    "COPY_JOB_FAILED",
    "RECOVERY_POINT_MODIFIED",
    "BACKUP_PLAN_MODIFIED",
    "BACKUP_JOB_SUSPENDED"
  ]
}

# ========================================
# AWS Backup Plan with Multi-Region Copy
# ========================================

# Main backup plan with daily and weekly backup rules
resource "aws_backup_plan" "multi_region" {
  provider = aws.primary
  name     = var.backup_plan_name

  # Daily backup rule with cross-region copy to secondary region
  rule {
    rule_name                = "DailyBackupWithCrossRegionCopy"
    target_vault_name        = aws_backup_vault.primary.name
    schedule                 = var.daily_backup_schedule
    start_window             = var.backup_start_window_minutes
    completion_window        = var.backup_completion_window_minutes
    enable_continuous_backup = false

    lifecycle {
      cold_storage_after = var.cold_storage_after_days
      delete_after       = var.daily_retention_days
    }

    # Cross-region copy to secondary region
    copy_action {
      destination_vault_arn = aws_backup_vault.secondary.arn
      
      lifecycle {
        cold_storage_after = var.cold_storage_after_days
        delete_after       = var.daily_retention_days
      }
    }

    recovery_point_tags = {
      BackupType    = "Daily"
      Environment   = var.environment
      CrossRegion   = "true"
      SourceRegion  = var.primary_region
      TargetRegion  = var.secondary_region
    }
  }

  # Weekly backup rule with cross-region copy to tertiary region for long-term archival
  rule {
    rule_name                = "WeeklyLongTermArchival"
    target_vault_name        = aws_backup_vault.primary.name
    schedule                 = var.weekly_backup_schedule
    start_window             = var.backup_start_window_minutes
    completion_window        = var.backup_completion_window_minutes
    enable_continuous_backup = false

    lifecycle {
      cold_storage_after = var.weekly_cold_storage_after_days
      delete_after       = var.weekly_retention_days
    }

    # Cross-region copy to tertiary region for archival
    copy_action {
      destination_vault_arn = aws_backup_vault.tertiary.arn
      
      lifecycle {
        cold_storage_after = var.weekly_cold_storage_after_days
        delete_after       = var.weekly_retention_days
      }
    }

    recovery_point_tags = {
      BackupType    = "Weekly"
      Environment   = var.environment
      LongTerm      = "true"
      SourceRegion  = var.primary_region
      TargetRegion  = var.tertiary_region
    }
  }

  # Advanced backup settings for Windows VSS (when enabled)
  dynamic "advanced_backup_setting" {
    for_each = var.enable_windows_vss ? [1] : []
    
    content {
      backup_options = {
        WindowsVSS = "enabled"
      }
      resource_type = "EC2"
    }
  }

  tags = merge(local.common_tags, {
    Name = var.backup_plan_name
  })
}

# ========================================
# Backup Selection for Resource Assignment
# ========================================

# Backup selection using tag-based resource discovery
resource "aws_backup_selection" "production_resources" {
  provider     = aws.primary
  iam_role_arn = aws_iam_role.backup_service_role.arn
  name         = "${local.resource_prefix}-production-resources-selection"
  plan_id      = aws_backup_plan.multi_region.id

  resources = ["*"]

  # Select resources based on tags
  dynamic "condition" {
    for_each = var.backup_resource_tags
    
    content {
      string_equals = [
        {
          key   = "aws:ResourceTag/${condition.key}"
          value = condition.value
        }
      ]
    }
  }
}

# ========================================
# EventBridge Rules for Backup Monitoring
# ========================================

# EventBridge rule for backup job state changes
resource "aws_cloudwatch_event_rule" "backup_job_state_change" {
  provider    = aws.primary
  name        = "${local.resource_prefix}-backup-job-state-change"
  description = "Capture backup job state changes"

  event_pattern = jsonencode({
    source      = ["aws.backup"]
    detail-type = ["Backup Job State Change"]
    detail = {
      state = ["COMPLETED", "FAILED", "EXPIRED", "ABORTED"]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-backup-job-state-change"
  })
}

# EventBridge rule for copy job state changes
resource "aws_cloudwatch_event_rule" "backup_copy_job_state_change" {
  provider    = aws.primary
  name        = "${local.resource_prefix}-backup-copy-job-state-change"
  description = "Capture backup copy job state changes"

  event_pattern = jsonencode({
    source      = ["aws.backup"]
    detail-type = ["Copy Job State Change"]
    detail = {
      state = ["COMPLETED", "FAILED"]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-backup-copy-job-state-change"
  })
}

# EventBridge targets for SNS notifications (when enabled)
resource "aws_cloudwatch_event_target" "backup_job_notification" {
  count     = var.enable_sns_notifications ? 1 : 0
  provider  = aws.primary
  rule      = aws_cloudwatch_event_rule.backup_job_state_change.name
  target_id = "BackupJobNotificationTarget"
  arn       = aws_sns_topic.backup_notifications[0].arn
}

resource "aws_cloudwatch_event_target" "backup_copy_job_notification" {
  count     = var.enable_sns_notifications ? 1 : 0
  provider  = aws.primary
  rule      = aws_cloudwatch_event_rule.backup_copy_job_state_change.name
  target_id = "BackupCopyJobNotificationTarget"
  arn       = aws_sns_topic.backup_notifications[0].arn
}

# ========================================
# Lambda Function for Backup Validation
# ========================================

# Create Lambda execution role when validation is enabled
resource "aws_iam_role" "backup_validator_role" {
  count    = var.enable_backup_validation ? 1 : 0
  provider = aws.primary
  name     = "${local.resource_prefix}-backup-validator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-backup-validator-role"
  })
}

# Attach basic execution role policy
resource "aws_iam_role_policy_attachment" "backup_validator_basic" {
  count      = var.enable_backup_validation ? 1 : 0
  provider   = aws.primary
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.backup_validator_role[0].name
}

# Custom IAM policy for backup validation operations
data "aws_iam_policy_document" "backup_validator_policy" {
  count = var.enable_backup_validation ? 1 : 0
  
  statement {
    effect = "Allow"
    
    actions = [
      "backup:DescribeBackupJob",
      "backup:ListCopyJobs",
      "backup:DescribeRecoveryPoint",
      "backup:DescribeCopyJob",
      "sns:Publish"
    ]
    
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "backup_validator_policy" {
  count    = var.enable_backup_validation ? 1 : 0
  provider = aws.primary
  name     = "${local.resource_prefix}-backup-validator-policy"
  role     = aws_iam_role.backup_validator_role[0].id
  policy   = data.aws_iam_policy_document.backup_validator_policy[0].json
}

# Lambda function for backup validation
resource "aws_lambda_function" "backup_validator" {
  count         = var.enable_backup_validation ? 1 : 0
  provider      = aws.primary
  filename      = "${path.module}/backup_validator.zip"
  function_name = "${local.resource_prefix}-backup-validator"
  role          = aws_iam_role.backup_validator_role[0].arn
  handler       = "backup_validator.lambda_handler"
  runtime       = "python3.11"
  timeout       = var.lambda_timeout

  environment {
    variables = {
      SNS_TOPIC_ARN = var.enable_sns_notifications ? aws_sns_topic.backup_notifications[0].arn : ""
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-backup-validator"
  })

  # Create the Lambda deployment package
  depends_on = [data.archive_file.backup_validator_zip]
}

# Create Lambda deployment package
data "archive_file" "backup_validator_zip" {
  count       = var.enable_backup_validation ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/backup_validator.zip"
  
  source {
    content = templatefile("${path.module}/backup_validator.py.tpl", {
      sns_topic_arn = var.enable_sns_notifications ? aws_sns_topic.backup_notifications[0].arn : ""
    })
    filename = "backup_validator.py"
  }
}

# EventBridge targets for Lambda validation
resource "aws_cloudwatch_event_target" "backup_validation" {
  count     = var.enable_backup_validation ? 1 : 0
  provider  = aws.primary
  rule      = aws_cloudwatch_event_rule.backup_job_state_change.name
  target_id = "BackupValidationTarget"
  arn       = aws_lambda_function.backup_validator[0].arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "backup_eventbridge_trigger" {
  count         = var.enable_backup_validation ? 1 : 0
  provider      = aws.primary
  statement_id  = "${local.resource_prefix}-backup-eventbridge-trigger"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_validator[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.backup_job_state_change.arn
}