# ==========================================================================
# AWS Transfer Family Web App - Secure Self-Service File Portal
# ==========================================================================
# This Terraform configuration creates a complete secure file portal using
# AWS Transfer Family Web Apps with IAM Identity Center integration and
# S3 Access Grants for fine-grained permission management.

# Data sources for existing AWS infrastructure
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common tags for all resources
  common_tags = {
    Environment   = var.environment
    Project       = "SecureFilePortal"
    Owner         = "Transfer-Family"
    CreatedBy     = "Terraform"
    Recipe        = "secure-self-service-file-portals-transfer-family-web-apps"
    CostCenter    = var.cost_center
  }

  # Resource naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  bucket_name = "${local.name_prefix}-files-${random_id.suffix.hex}"
  
  # IAM Identity Center configuration
  identity_center_required = var.create_identity_center_user
}

# ==========================================================================
# S3 BUCKET FOR FILE STORAGE
# ==========================================================================

# Primary S3 bucket for file storage with enterprise security features
resource "aws_s3_bucket" "file_portal" {
  bucket = local.bucket_name
  tags   = merge(local.common_tags, {
    Name = "${local.name_prefix}-file-bucket"
    Type = "FileStorage"
  })
}

# Enable versioning for file history and compliance
resource "aws_s3_bucket_versioning" "file_portal" {
  bucket = aws_s3_bucket.file_portal.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption with AES-256 for data protection
resource "aws_s3_bucket_server_side_encryption_configuration" "file_portal" {
  bucket = aws_s3_bucket.file_portal.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access for security compliance
resource "aws_s3_bucket_public_access_block" "file_portal" {
  bucket = aws_s3_bucket.file_portal.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Access logging for compliance and audit requirements
resource "aws_s3_bucket_logging" "file_portal" {
  bucket = aws_s3_bucket.file_portal.id

  target_bucket = aws_s3_bucket.file_portal.id
  target_prefix = "access-logs/"
}

# Lifecycle configuration to manage costs
resource "aws_s3_bucket_lifecycle_configuration" "file_portal" {
  depends_on = [aws_s3_bucket_versioning.file_portal]
  bucket     = aws_s3_bucket.file_portal.id

  rule {
    id     = "lifecycle-rule"
    status = "Enabled"

    # Archive old versions to reduce costs
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 60
      storage_class   = "GLACIER"
    }

    # Delete old versions after 365 days
    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ==========================================================================
# IAM IDENTITY CENTER INTEGRATION
# ==========================================================================

# Data source to get existing IAM Identity Center instance
data "aws_ssoadmin_instances" "main" {}

locals {
  # Use the first (usually only) Identity Center instance
  identity_center_instance_arn    = length(data.aws_ssoadmin_instances.main.arns) > 0 ? data.aws_ssoadmin_instances.main.arns[0] : null
  identity_center_identity_store_id = length(data.aws_ssoadmin_instances.main.identity_store_ids) > 0 ? data.aws_ssoadmin_instances.main.identity_store_ids[0] : null
}

# Create test user in IAM Identity Center (optional)
resource "aws_identitystore_user" "portal_user" {
  count             = var.create_identity_center_user ? 1 : 0
  identity_store_id = local.identity_center_identity_store_id

  display_name = var.test_user_display_name
  user_name    = var.test_user_name

  name {
    given_name  = var.test_user_given_name
    family_name = var.test_user_family_name
  }

  emails {
    value   = var.test_user_email
    type    = "work"
    primary = true
  }
}

# ==========================================================================
# S3 ACCESS GRANTS CONFIGURATION
# ==========================================================================

# Create S3 Access Grants instance with Identity Center integration
resource "aws_s3control_access_grants_instance" "main" {
  identity_center_arn = local.identity_center_instance_arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-access-grants"
  })
}

# IAM role for S3 Access Grants location operations
resource "aws_iam_role" "s3_access_grants_location" {
  name = "${local.name_prefix}-s3-access-grants-location-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-access-grants-location-role"
    Type = "ServiceRole"
  })
}

# Attach S3 permissions to the location role
resource "aws_iam_role_policy_attachment" "s3_access_grants_location" {
  role       = aws_iam_role.s3_access_grants_location.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Register S3 bucket as Access Grants location
resource "aws_s3control_access_grants_location" "main" {
  depends_on = [aws_s3control_access_grants_instance.main]

  location_scope = "s3://${aws_s3_bucket.file_portal.bucket}/*"
  iam_role_arn   = aws_iam_role.s3_access_grants_location.arn

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-s3-location"
    Purpose = "TransferFamilyWebApp"
  })
}

# Create access grant for test user (if created)
resource "aws_s3control_access_grant" "portal_user" {
  count = var.create_identity_center_user ? 1 : 0

  access_grants_location_id = aws_s3control_access_grants_location.main.access_grants_location_id
  permission                = "READWRITE"

  access_grants_location_configuration {
    s3_sub_prefix = "*"
  }

  grantee {
    grantee_type       = "DIRECTORY_USER"
    grantee_identifier = aws_identitystore_user.portal_user[0].user_id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-user-access-grant"
    User = aws_identitystore_user.portal_user[0].user_name
  })
}

# ==========================================================================
# TRANSFER FAMILY WEB APP
# ==========================================================================

# IAM role for Transfer Family Web App identity bearer operations
resource "aws_iam_role" "transfer_family_web_app" {
  name = "AWSTransferFamilyWebAppIdentityBearerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "AWSTransferFamilyWebAppIdentityBearerRole"
    Type = "ServiceRole"
  })
}

# Attach the managed policy for Transfer Family Web App
resource "aws_iam_role_policy_attachment" "transfer_family_web_app" {
  role       = aws_iam_role.transfer_family_web_app.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSTransferFamilyWebAppIdentityBearerRole"
}

# Create Transfer Family Web App with Identity Center integration
resource "aws_transfer_web_app" "main" {
  depends_on = [
    aws_s3control_access_grants_instance.main,
    aws_iam_role_policy_attachment.transfer_family_web_app
  ]

  identity_provider_type = "IDENTITY_CENTER"
  access_role            = aws_iam_role.transfer_family_web_app.arn
  web_app_units          = var.web_app_units

  identity_provider_details {
    identity_center_config {
      instance_arn = local.identity_center_instance_arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web-app"
    Type = "FilePortal"
  })
}

# ==========================================================================
# CORS CONFIGURATION FOR WEB APP
# ==========================================================================

# CORS configuration to enable web app access to S3 bucket
resource "aws_s3_bucket_cors_configuration" "file_portal" {
  depends_on = [aws_transfer_web_app.main]
  bucket     = aws_s3_bucket.file_portal.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["https://${aws_transfer_web_app.main.access_endpoint}"]
    expose_headers = [
      "last-modified",
      "content-length", 
      "etag",
      "x-amz-version-id",
      "content-type",
      "x-amz-request-id",
      "x-amz-id-2",
      "date",
      "x-amz-cf-id",
      "x-amz-storage-class"
    ]
    max_age_seconds = 3000
  }
}

# ==========================================================================
# CLOUDWATCH MONITORING AND LOGGING
# ==========================================================================

# CloudWatch Log Group for Transfer Family Web App
resource "aws_cloudwatch_log_group" "transfer_family" {
  name              = "/aws/transfer/webapp/${aws_transfer_web_app.main.web_app_id}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-transfer-logs"
    Type = "Logging"
  })
}

# CloudWatch Log Group for S3 access logs
resource "aws_cloudwatch_log_group" "s3_access" {
  name              = "/aws/s3/access-logs/${local.bucket_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-access-logs"
    Type = "Logging"
  })
}

# ==========================================================================
# SECURITY MONITORING
# ==========================================================================

# CloudWatch Metric Filter for failed login attempts
resource "aws_cloudwatch_log_metric_filter" "failed_logins" {
  name           = "${local.name_prefix}-failed-logins"
  log_group_name = aws_cloudwatch_log_group.transfer_family.name
  pattern        = "[timestamp, request_id, client_ip, user, event=\"AUTHENTICATION_FAILED\"]"

  metric_transformation {
    name      = "FailedLogins"
    namespace = "TransferFamily/Security"
    value     = "1"
  }
}

# CloudWatch Alarm for failed login attempts
resource "aws_cloudwatch_metric_alarm" "failed_logins" {
  alarm_name          = "${local.name_prefix}-failed-logins"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FailedLogins"
  namespace           = "TransferFamily/Security"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors failed login attempts"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-failed-logins-alarm"
    Type = "SecurityMonitoring"
  })
}

# ==========================================================================
# BACKUP CONFIGURATION
# ==========================================================================

# AWS Backup vault for S3 bucket backups
resource "aws_backup_vault" "file_portal" {
  count       = var.enable_backup ? 1 : 0
  name        = "${local.name_prefix}-backup-vault"
  kms_key_arn = var.backup_kms_key_arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backup-vault"
    Type = "Backup"
  })
}

# AWS Backup plan for regular S3 backups
resource "aws_backup_plan" "file_portal" {
  count = var.enable_backup ? 1 : 0
  name  = "${local.name_prefix}-backup-plan"

  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.file_portal[0].name
    schedule          = "cron(0 5 ? * * *)"  # Daily at 5 AM UTC

    recovery_point_tags = merge(local.common_tags, {
      BackupType = "Automated"
    })

    lifecycle {
      cold_storage_after = 30
      delete_after       = 120
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backup-plan"
    Type = "Backup"
  })
}

# IAM role for AWS Backup
resource "aws_iam_role" "backup" {
  count = var.enable_backup ? 1 : 0
  name  = "${local.name_prefix}-backup-role"

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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backup-role"
    Type = "ServiceRole"
  })
}

# Attach backup service policy
resource "aws_iam_role_policy_attachment" "backup" {
  count      = var.enable_backup ? 1 : 0
  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForS3Backup"
}

# Backup selection for S3 bucket
resource "aws_backup_selection" "file_portal" {
  count        = var.enable_backup ? 1 : 0
  iam_role_arn = aws_iam_role.backup[0].arn
  name         = "${local.name_prefix}-backup-selection"
  plan_id      = aws_backup_plan.file_portal[0].id

  resources = [
    aws_s3_bucket.file_portal.arn
  ]

  condition {
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.environment
    }
  }
}