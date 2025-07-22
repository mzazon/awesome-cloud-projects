# Main Terraform configuration for secure file sharing with AWS Transfer Family
# This configuration implements a complete secure file sharing solution with web apps,
# S3 storage, audit logging, and identity integration

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 8
}

# Local values for consistent resource naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  bucket_name = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Recipe      = "secure-file-sharing-transfer-family-web-apps"
  }
}

# =============================================================================
# KMS ENCRYPTION KEYS
# =============================================================================

# KMS key for S3 bucket encryption
resource "aws_kms_key" "s3_encryption" {
  description             = "KMS key for S3 bucket encryption in secure file sharing"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-encryption-key"
    Purpose = "S3Encryption"
  })
}

# KMS key alias for S3 encryption
resource "aws_kms_alias" "s3_encryption" {
  name          = "alias/${local.name_prefix}-s3-encryption"
  target_key_id = aws_kms_key.s3_encryption.key_id
}

# KMS key for CloudTrail encryption
resource "aws_kms_key" "cloudtrail_encryption" {
  count = var.enable_cloudtrail ? 1 : 0
  
  description             = "KMS key for CloudTrail encryption in secure file sharing"
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
        Sid    = "Allow CloudTrail to encrypt logs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cloudtrail-encryption-key"
    Purpose = "CloudTrailEncryption"
  })
}

# KMS key alias for CloudTrail encryption
resource "aws_kms_alias" "cloudtrail_encryption" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name          = "alias/${local.name_prefix}-cloudtrail-encryption"
  target_key_id = aws_kms_key.cloudtrail_encryption[0].key_id
}

# =============================================================================
# S3 BUCKET CONFIGURATION
# =============================================================================

# Main S3 bucket for file storage
resource "aws_s3_bucket" "file_storage" {
  bucket        = local.bucket_name
  force_destroy = true # Only for development - remove in production

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-file-storage"
    Purpose = "FileStorage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_encryption.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for security
resource "aws_s3_bucket_public_access_block" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "file_storage" {
  count  = var.s3_lifecycle_enable ? 1 : 0
  bucket = aws_s3_bucket.file_storage.id

  rule {
    id     = "lifecycle_rule"
    status = "Enabled"

    # Archive folder specific lifecycle
    filter {
      prefix = "archive/"
    }

    transition {
      days          = var.s3_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_transition_to_glacier_days
      storage_class = "GLACIER"
    }

    # Delete incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "backup_cleanup"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    expiration {
      days = var.backup_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.file_storage]
}

# S3 bucket notification configuration for audit logging
resource "aws_s3_bucket_notification" "file_storage" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.file_storage.id

  # CloudWatch Events for file operations
  eventbridge = true
}

# =============================================================================
# CLOUDTRAIL CONFIGURATION FOR AUDIT LOGGING
# =============================================================================

# CloudTrail S3 bucket for audit logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket        = "${local.bucket_name}-cloudtrail-logs"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cloudtrail-logs"
    Purpose = "AuditLogs"
  })
}

# CloudTrail logs bucket versioning
resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# CloudTrail logs bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.cloudtrail_encryption[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# CloudTrail logs bucket public access block
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudTrail bucket policy
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs[0].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudWatch Log Group for CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name              = "/aws/cloudtrail/${local.name_prefix}"
  retention_in_days = var.cloudtrail_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cloudtrail-logs"
  })
}

# IAM role for CloudTrail CloudWatch Logs
resource "aws_iam_role" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name = "${local.name_prefix}-cloudtrail-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM role policy for CloudTrail CloudWatch Logs
resource "aws_iam_role_policy" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name = "${local.name_prefix}-cloudtrail-logs-policy"
  role = aws_iam_role.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
      }
    ]
  })
}

# CloudTrail configuration
resource "aws_cloudtrail" "file_sharing_audit" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name           = "${local.name_prefix}-audit-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs[0].id
  s3_key_prefix  = "audit-logs"

  # CloudWatch Logs configuration
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_logs[0].arn

  # Encryption and validation
  kms_key_id                = aws_kms_key.cloudtrail_encryption[0].arn
  enable_log_file_validation = true

  # Multi-region and global services
  include_global_service_events = true
  is_multi_region_trail        = true

  # Data events for S3 bucket
  advanced_event_selector {
    name = "S3 Transfer Bucket Data Events"
    
    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    
    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }
    
    field_selector {
      field       = "resources.ARN"
      starts_with = ["${aws_s3_bucket.file_storage.arn}/"]
    }
  }

  # Management events
  advanced_event_selector {
    name = "Management Events"
    
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-audit-trail"
    Purpose = "AuditLogging"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}

# =============================================================================
# IAM ROLES AND POLICIES FOR TRANSFER FAMILY
# =============================================================================

# IAM role for Transfer Family server
resource "aws_iam_role" "transfer_server" {
  name = "${local.name_prefix}-transfer-server-role"

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
    Name = "${local.name_prefix}-transfer-server-role"
    Purpose = "TransferFamilyServer"
  })
}

# IAM role policy for Transfer Family S3 access
resource "aws_iam_role_policy" "transfer_s3_access" {
  name = "${local.name_prefix}-transfer-s3-access"
  role = aws_iam_role.transfer_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.file_storage.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ]
        Resource = "${aws_s3_bucket.file_storage.arn}/*"
      }
    ]
  })
}

# IAM role for Transfer Family logging
resource "aws_iam_role" "transfer_logging" {
  name = "${local.name_prefix}-transfer-logging-role"

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
    Name = "${local.name_prefix}-transfer-logging-role"
    Purpose = "TransferFamilyLogging"
  })
}

# Attach AWS managed policy for Transfer Family logging
resource "aws_iam_role_policy_attachment" "transfer_logging" {
  role       = aws_iam_role.transfer_logging.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSTransferLoggingAccess"
}

# =============================================================================
# CLOUDWATCH LOG GROUP FOR TRANSFER FAMILY
# =============================================================================

# CloudWatch Log Group for Transfer Family server logs
resource "aws_cloudwatch_log_group" "transfer_server" {
  name              = "/aws/transfer/${local.name_prefix}-server"
  retention_in_days = var.cloudtrail_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-transfer-server-logs"
    Purpose = "TransferServerLogs"
  })
}

# =============================================================================
# TRANSFER FAMILY SERVER CONFIGURATION
# =============================================================================

# Transfer Family server
resource "aws_transfer_server" "secure_server" {
  identity_provider_type   = "SERVICE_MANAGED"
  endpoint_type           = var.transfer_server_endpoint_type
  protocols               = var.transfer_protocols
  security_policy_name    = "TransferSecurityPolicy-2024-01"
  logging_role            = aws_iam_role.transfer_logging.arn

  structured_log_destinations = [
    "${aws_cloudwatch_log_group.transfer_server.arn}:*"
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-transfer-server"
    Purpose = "SecureFileTransfer"
  })
}

# =============================================================================
# TRANSFER FAMILY WEB APP CONFIGURATION
# =============================================================================

# Transfer Family Web App (if supported by provider)
# Note: Web App resource may not be available in all provider versions
# This is a placeholder for when the resource becomes available

# =============================================================================
# TEST USER CONFIGURATION
# =============================================================================

# Test user for Transfer Family server
resource "aws_transfer_user" "test_user" {
  server_id      = aws_transfer_server.secure_server.id
  user_name      = var.test_user_name
  role           = aws_iam_role.transfer_server.arn
  home_directory = var.test_user_home_directory

  home_directory_type = "LOGICAL"
  home_directory_mappings {
    entry  = "/"
    target = "/${aws_s3_bucket.file_storage.bucket}"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.test_user_name}"
    Purpose = "TestUser"
  })
}

# =============================================================================
# SAMPLE FILE STRUCTURE
# =============================================================================

# Sample welcome file
resource "aws_s3_object" "welcome_file" {
  bucket       = aws_s3_bucket.file_storage.bucket
  key          = "welcome.txt"
  content      = "Welcome to Secure File Sharing Portal\nThis is a secure file sharing solution powered by AWS Transfer Family."
  content_type = "text/plain"

  server_side_encryption = "aws:kms"
  kms_key_id            = aws_kms_key.s3_encryption.arn

  tags = merge(local.common_tags, {
    Name = "welcome-file"
    Purpose = "SampleContent"
  })
}

# Sample upload directory structure
resource "aws_s3_object" "uploads_folder" {
  bucket       = aws_s3_bucket.file_storage.bucket
  key          = "uploads/"
  content_type = "application/x-directory"

  server_side_encryption = "aws:kms"
  kms_key_id            = aws_kms_key.s3_encryption.arn

  tags = merge(local.common_tags, {
    Name = "uploads-folder"
    Purpose = "FolderStructure"
  })
}

# Sample shared directory structure
resource "aws_s3_object" "shared_folder" {
  bucket       = aws_s3_bucket.file_storage.bucket
  key          = "shared/"
  content_type = "application/x-directory"

  server_side_encryption = "aws:kms"
  kms_key_id            = aws_kms_key.s3_encryption.arn

  tags = merge(local.common_tags, {
    Name = "shared-folder"
    Purpose = "FolderStructure"
  })
}

# Sample archive directory structure
resource "aws_s3_object" "archive_folder" {
  bucket       = aws_s3_bucket.file_storage.bucket
  key          = "archive/"
  content_type = "application/x-directory"

  server_side_encryption = "aws:kms"
  kms_key_id            = aws_kms_key.s3_encryption.arn

  tags = merge(local.common_tags, {
    Name = "archive-folder"
    Purpose = "FolderStructure"
  })
}

# Sample file in uploads folder
resource "aws_s3_object" "sample_upload" {
  bucket       = aws_s3_bucket.file_storage.bucket
  key          = "uploads/sample.txt"
  content      = "Sample document for testing upload functionality"
  content_type = "text/plain"

  server_side_encryption = "aws:kms"
  kms_key_id            = aws_kms_key.s3_encryption.arn

  tags = merge(local.common_tags, {
    Name = "sample-upload-file"
    Purpose = "SampleContent"
  })
}

# Sample file in shared folder
resource "aws_s3_object" "sample_shared" {
  bucket       = aws_s3_bucket.file_storage.bucket
  key          = "shared/resource.txt"
  content      = "Shared resource document for collaboration"
  content_type = "text/plain"

  server_side_encryption = "aws:kms"
  kms_key_id            = aws_kms_key.s3_encryption.arn

  tags = merge(local.common_tags, {
    Name = "sample-shared-file"
    Purpose = "SampleContent"
  })
}

# Sample file in archive folder
resource "aws_s3_object" "sample_archive" {
  bucket       = aws_s3_bucket.file_storage.bucket
  key          = "archive/archive.txt"
  content      = "Archived document for long-term storage"
  content_type = "text/plain"

  server_side_encryption = "aws:kms"
  kms_key_id            = aws_kms_key.s3_encryption.arn

  tags = merge(local.common_tags, {
    Name = "sample-archive-file"
    Purpose = "SampleContent"
  })
}