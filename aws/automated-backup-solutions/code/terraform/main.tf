# AWS Backup Automated Solution Infrastructure
# This Terraform configuration creates a comprehensive AWS Backup solution
# with automated backup plans, cross-region replication, and monitoring

terraform {
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

# Configure the primary AWS Provider
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = var.default_tags
  }
}

# Configure the disaster recovery AWS Provider
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = var.default_tags
  }
}

# Data sources for current AWS account and caller identity
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  random_suffix = random_id.suffix.hex
  
  # Standardized resource naming
  backup_vault_name       = "${var.backup_vault_prefix}-${local.random_suffix}"
  dr_backup_vault_name    = "${var.dr_backup_vault_prefix}-${local.random_suffix}"
  backup_plan_name        = "${var.backup_plan_prefix}-${local.random_suffix}"
  sns_topic_name          = "${var.sns_topic_prefix}-${local.random_suffix}"
  iam_role_name          = var.backup_service_role_name
  s3_reports_bucket_name = "${var.s3_reports_bucket_prefix}-${local.account_id}-${var.primary_region}"
  
  # Common tags to be applied to all resources
  common_tags = merge(var.default_tags, {
    Project     = "AWS-Backup-Solution"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ====================================
# IAM ROLES AND POLICIES
# ====================================

# IAM service role for AWS Backup
resource "aws_iam_role" "backup_service_role" {
  name = local.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  description = "Service role for AWS Backup operations"
  
  tags = merge(local.common_tags, {
    Name = local.iam_role_name
  })
}

# Attach AWS managed backup policy
resource "aws_iam_role_policy_attachment" "backup_service_policy" {
  role       = aws_iam_role.backup_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# Attach AWS managed restore policy
resource "aws_iam_role_policy_attachment" "restore_service_policy" {
  role       = aws_iam_role.backup_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Additional policy for S3 and SNS operations
resource "aws_iam_role_policy" "backup_additional_permissions" {
  name = "${local.iam_role_name}-additional-permissions"
  role = aws_iam_role.backup_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketNotification",
          "s3:PutBucketNotification",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          aws_s3_bucket.backup_reports.arn,
          "${aws_s3_bucket.backup_reports.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.backup_notifications.arn
        ]
      }
    ]
  })
}

# ====================================
# BACKUP VAULTS
# ====================================

# Primary region backup vault
resource "aws_backup_vault" "primary" {
  provider = aws.primary
  
  name        = local.backup_vault_name
  kms_key_arn = aws_kms_key.backup_key.arn

  tags = merge(local.common_tags, {
    Name   = local.backup_vault_name
    Region = "Primary"
  })
}

# Disaster recovery region backup vault
resource "aws_backup_vault" "dr" {
  provider = aws.dr
  
  name        = local.dr_backup_vault_name
  kms_key_arn = aws_kms_key.backup_key_dr.arn

  tags = merge(local.common_tags, {
    Name   = local.dr_backup_vault_name
    Region = "DR"
  })
}

# ====================================
# KMS ENCRYPTION KEYS
# ====================================

# KMS key for backup encryption in primary region
resource "aws_kms_key" "backup_key" {
  provider = aws.primary
  
  description             = "KMS key for AWS Backup encryption in primary region"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow AWS Backup to use the key"
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
    Name = "${local.backup_vault_name}-key"
  })
}

# KMS key alias for primary region
resource "aws_kms_alias" "backup_key_alias" {
  provider = aws.primary
  
  name          = "alias/${local.backup_vault_name}-key"
  target_key_id = aws_kms_key.backup_key.key_id
}

# KMS key for backup encryption in DR region
resource "aws_kms_key" "backup_key_dr" {
  provider = aws.dr
  
  description             = "KMS key for AWS Backup encryption in DR region"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow AWS Backup to use the key"
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
    Name = "${local.dr_backup_vault_name}-key"
  })
}

# KMS key alias for DR region
resource "aws_kms_alias" "backup_key_alias_dr" {
  provider = aws.dr
  
  name          = "alias/${local.dr_backup_vault_name}-key"
  target_key_id = aws_kms_key.backup_key_dr.key_id
}

# ====================================
# BACKUP PLANS
# ====================================

# Comprehensive backup plan with multiple schedules
resource "aws_backup_plan" "enterprise_backup" {
  provider = aws.primary
  
  name = local.backup_plan_name

  # Daily backup rule
  rule {
    rule_name                = "DailyBackups"
    target_vault_name        = aws_backup_vault.primary.name
    schedule                 = var.daily_backup_schedule
    start_window             = var.backup_start_window_minutes
    completion_window        = var.backup_completion_window_minutes
    enable_continuous_backup = var.enable_continuous_backup

    lifecycle {
      delete_after = var.daily_backup_retention_days
    }

    recovery_point_tags = merge(local.common_tags, {
      BackupType = "Daily"
      Schedule   = "Automated"
    })

    # Cross-region copy for disaster recovery
    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn

      lifecycle {
        delete_after = var.daily_backup_retention_days
      }
    }
  }

  # Weekly backup rule for longer retention
  rule {
    rule_name                = "WeeklyBackups"
    target_vault_name        = aws_backup_vault.primary.name
    schedule                 = var.weekly_backup_schedule
    start_window             = var.backup_start_window_minutes
    completion_window        = var.weekly_backup_completion_window_minutes
    enable_continuous_backup = false

    lifecycle {
      delete_after = var.weekly_backup_retention_days
    }

    recovery_point_tags = merge(local.common_tags, {
      BackupType = "Weekly"
      Schedule   = "Automated"
    })

    # Cross-region copy for disaster recovery
    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn

      lifecycle {
        delete_after = var.weekly_backup_retention_days
      }
    }
  }

  # Monthly backup rule for compliance and archival
  rule {
    rule_name                = "MonthlyBackups"
    target_vault_name        = aws_backup_vault.primary.name
    schedule                 = var.monthly_backup_schedule
    start_window             = var.backup_start_window_minutes
    completion_window        = var.monthly_backup_completion_window_minutes
    enable_continuous_backup = false

    lifecycle {
      delete_after = var.monthly_backup_retention_days
    }

    recovery_point_tags = merge(local.common_tags, {
      BackupType = "Monthly"
      Schedule   = "Automated"
    })

    # Cross-region copy for disaster recovery
    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn

      lifecycle {
        delete_after = var.monthly_backup_retention_days
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = local.backup_plan_name
  })
}

# ====================================
# BACKUP SELECTIONS
# ====================================

# Backup selection for production resources
resource "aws_backup_selection" "production_resources" {
  provider = aws.primary
  
  iam_role_arn = aws_iam_role.backup_service_role.arn
  name         = "ProductionResources"
  plan_id      = aws_backup_plan.enterprise_backup.id

  # Select all resources with specific tags
  resources = ["*"]

  condition {
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.environment
    }
  }

  condition {
    string_equals {
      key   = "aws:ResourceTag/BackupEnabled"
      value = "true"
    }
  }

  # Exclude test and development resources
  not_resources = var.backup_exclusion_resources
}

# Additional backup selection for critical databases
resource "aws_backup_selection" "critical_databases" {
  provider = aws.primary
  
  iam_role_arn = aws_iam_role.backup_service_role.arn
  name         = "CriticalDatabases"
  plan_id      = aws_backup_plan.enterprise_backup.id

  # Select specific resource types
  resources = ["*"]

  condition {
    string_equals {
      key   = "aws:ResourceTag/CriticalData"
      value = "true"
    }
  }

  condition {
    string_like {
      key   = "aws:ResourceTag/ResourceType"
      value = "Database*"
    }
  }
}

# ====================================
# MONITORING AND NOTIFICATIONS
# ====================================

# SNS topic for backup notifications
resource "aws_sns_topic" "backup_notifications" {
  provider = aws.primary
  
  name = local.sns_topic_name

  tags = merge(local.common_tags, {
    Name = local.sns_topic_name
  })
}

# SNS topic policy to allow AWS Backup to publish
resource "aws_sns_topic_policy" "backup_notifications_policy" {
  provider = aws.primary
  
  arn = aws_sns_topic.backup_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAWSBackupToPublish"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.backup_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# Email subscription for backup notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  provider = aws.primary
  count    = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.backup_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Backup vault notifications
resource "aws_backup_vault_notifications" "primary_vault_notifications" {
  provider = aws.primary
  
  backup_vault_name   = aws_backup_vault.primary.name
  sns_topic_arn       = aws_sns_topic.backup_notifications.arn
  backup_vault_events = var.backup_vault_events
}

# ====================================
# CLOUDWATCH MONITORING
# ====================================

# CloudWatch alarm for backup job failures
resource "aws_cloudwatch_metric_alarm" "backup_job_failures" {
  provider = aws.primary
  
  alarm_name          = "AWS-Backup-Job-Failures-${local.random_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors backup job failures"
  alarm_actions       = [aws_sns_topic.backup_notifications.arn]
  treat_missing_data  = "notBreaching"

  tags = merge(local.common_tags, {
    Name = "AWS-Backup-Job-Failures-${local.random_suffix}"
  })
}

# CloudWatch alarm for backup storage usage
resource "aws_cloudwatch_metric_alarm" "backup_storage_usage" {
  provider = aws.primary
  
  alarm_name          = "AWS-Backup-Storage-Usage-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BackupVaultSizeBytes"
  namespace           = "AWS/Backup"
  period              = "3600"
  statistic           = "Average"
  threshold           = var.backup_storage_threshold_bytes
  alarm_description   = "This metric monitors backup vault storage usage"
  alarm_actions       = [aws_sns_topic.backup_notifications.arn]

  dimensions = {
    BackupVaultName = aws_backup_vault.primary.name
  }

  tags = merge(local.common_tags, {
    Name = "AWS-Backup-Storage-Usage-${local.random_suffix}"
  })
}

# ====================================
# BACKUP VAULT SECURITY
# ====================================

# Backup vault lock configuration for immutable backups
resource "aws_backup_vault_lock_configuration" "primary_vault_lock" {
  provider = aws.primary
  count    = var.enable_backup_vault_lock ? 1 : 0
  
  backup_vault_name   = aws_backup_vault.primary.name
  changeable_for_days = var.backup_vault_lock_changeable_days
  max_retention_days  = var.backup_vault_lock_max_retention_days
  min_retention_days  = var.backup_vault_lock_min_retention_days
}

# Backup vault access policy for enhanced security
resource "aws_backup_vault_policy" "primary_vault_policy" {
  provider = aws.primary
  
  backup_vault_name = aws_backup_vault.primary.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyDeleteBackupVault"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "backup:DeleteBackupVault",
          "backup:DeleteRecoveryPoint",
          "backup:UpdateRecoveryPointLifecycle"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:userid" = ["${local.account_id}:root"]
          }
        }
      }
    ]
  })
}

# ====================================
# REPORTING AND COMPLIANCE
# ====================================

# S3 bucket for backup reports
resource "aws_s3_bucket" "backup_reports" {
  provider = aws.primary
  
  bucket = local.s3_reports_bucket_name

  tags = merge(local.common_tags, {
    Name = local.s3_reports_bucket_name
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "backup_reports_versioning" {
  provider = aws.primary
  
  bucket = aws_s3_bucket.backup_reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "backup_reports_encryption" {
  provider = aws.primary
  
  bucket = aws_s3_bucket.backup_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "backup_reports_pab" {
  provider = aws.primary
  
  bucket = aws_s3_bucket.backup_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Backup reporting plan
resource "aws_backup_report_plan" "backup_compliance_report" {
  provider = aws.primary
  count    = var.enable_backup_reporting ? 1 : 0
  
  name        = "backup-compliance-report-${local.random_suffix}"
  description = "Monthly backup compliance report"

  report_delivery_channel {
    s3_bucket_name = aws_s3_bucket.backup_reports.bucket
    s3_key_prefix  = "backup-reports/"
    formats        = ["CSV", "JSON"]
  }

  report_setting {
    report_template = "BACKUP_JOB_REPORT"
  }

  tags = merge(local.common_tags, {
    Name = "backup-compliance-report-${local.random_suffix}"
  })
}

# ====================================
# AWS CONFIG COMPLIANCE RULES
# ====================================

# Config rule for backup plan compliance
resource "aws_config_config_rule" "backup_plan_compliance" {
  provider = aws.primary
  count    = var.enable_config_compliance ? 1 : 0
  
  name = "backup-plan-min-frequency-and-min-retention-check-${local.random_suffix}"

  source {
    owner             = "AWS"
    source_identifier = "BACKUP_PLAN_MIN_FREQUENCY_AND_MIN_RETENTION_CHECK"
  }

  input_parameters = jsonencode({
    requiredFrequencyValue = var.config_required_frequency_value
    requiredRetentionDays  = var.config_required_retention_days
    requiredFrequencyUnit  = var.config_required_frequency_unit
  })

  depends_on = [aws_backup_plan.enterprise_backup]

  tags = merge(local.common_tags, {
    Name = "backup-plan-compliance-${local.random_suffix}"
  })
}

# ====================================
# RESTORE TESTING
# ====================================

# Restore testing plan for automated validation
resource "aws_backup_restore_testing_plan" "automated_restore_test" {
  provider = aws.primary
  count    = var.enable_restore_testing ? 1 : 0
  
  name = "automated-restore-test-${local.random_suffix}"

  recovery_point_selection {
    algorithm                = "LATEST_WITHIN_WINDOW"
    recovery_point_types     = ["SNAPSHOT"]
    include_vaults           = [aws_backup_vault.primary.arn]
    exclude_vaults           = []
    selection_window_days    = var.restore_testing_selection_window_days
  }

  schedule_expression = var.restore_testing_schedule

  tags = merge(local.common_tags, {
    Name = "automated-restore-test-${local.random_suffix}"
  })
}