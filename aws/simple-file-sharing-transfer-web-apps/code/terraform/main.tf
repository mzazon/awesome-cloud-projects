# AWS Transfer Family Web Apps - Main Terraform Configuration
# This file contains the complete infrastructure for Simple File Sharing with Transfer Family Web Apps

# =============================================================================
# Data Sources - Current AWS Environment Information
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# Get IAM Identity Center instance information
data "aws_ssoadmin_instances" "main" {}

# =============================================================================
# Local Values - Computed Configuration
# =============================================================================

locals {
  # Account and region information
  account_id = data.aws_caller_identity.current.account_id
  region     = var.region != null ? var.region : data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  # IAM Identity Center configuration
  identity_center_arn = var.identity_center_arn_override != null ? var.identity_center_arn_override : (
    length(data.aws_ssoadmin_instances.main.arns) > 0 ? data.aws_ssoadmin_instances.main.arns[0] : null
  )
  identity_store_id = length(data.aws_ssoadmin_instances.main.identity_store_ids) > 0 ? data.aws_ssoadmin_instances.main.identity_store_ids[0] : null

  # Resource naming
  resource_prefix = "${var.project_name}-${var.environment}"
  bucket_name = var.bucket_name_override != null ? var.bucket_name_override : "${local.resource_prefix}-${random_id.suffix.hex}"

  # Common tags applied to all resources
  common_tags = merge(
    {
      Environment       = var.environment
      Project          = var.project_name
      ManagedBy        = "terraform"
      Purpose          = "transfer-family-web-apps"
      CostCenter       = var.cost_center
      DataClassification = var.data_classification
      CreatedBy        = data.aws_caller_identity.current.user_id
      CreatedDate      = timestamp()
    },
    var.additional_tags
  )
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# =============================================================================
# IAM Identity Center Validation
# =============================================================================

# Check that IAM Identity Center is properly configured
resource "null_resource" "identity_center_check" {
  count = local.identity_center_arn == null ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      echo "ERROR: IAM Identity Center is not enabled or configured in this account."
      echo "Please enable IAM Identity Center before deploying this infrastructure."
      echo "Visit: https://console.aws.amazon.com/singlesignon/"
      exit 1
    EOT
  }
}

# =============================================================================
# S3 Bucket for File Storage
# =============================================================================

# Primary S3 bucket for file sharing storage
resource "aws_s3_bucket" "file_sharing" {
  bucket        = local.bucket_name
  force_destroy = var.environment == "dev" ? true : false

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-file-sharing-bucket"
    Type = "FileStorage"
  })

  depends_on = [null_resource.identity_center_check]
}

# Configure S3 bucket versioning for file history tracking
resource "aws_s3_bucket_versioning" "file_sharing" {
  bucket = aws_s3_bucket.file_sharing.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# Configure server-side encryption for data protection
resource "aws_s3_bucket_server_side_encryption_configuration" "file_sharing" {
  count  = var.enable_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.file_sharing.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_id
      sse_algorithm     = var.kms_key_id != null ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.kms_key_id != null ? true : false
  }
}

# Block public access to ensure security
resource "aws_s3_bucket_public_access_block" "file_sharing" {
  count  = var.enable_bucket_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.file_sharing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Configure lifecycle rules for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "file_sharing" {
  count  = var.lifecycle_rules_enabled ? 1 : 0
  bucket = aws_s3_bucket.file_sharing.id

  rule {
    id     = "file_sharing_lifecycle"
    status = "Enabled"

    # Transition to IA after specified days
    dynamic "transition" {
      for_each = var.transition_to_ia_days > 0 ? [1] : []
      content {
        days          = var.transition_to_ia_days
        storage_class = "STANDARD_IA"
      }
    }

    # Transition to Glacier after specified days
    dynamic "transition" {
      for_each = var.transition_to_glacier_days > 0 ? [1] : []
      content {
        days          = var.transition_to_glacier_days
        storage_class = "GLACIER"
      }
    }

    # Expire objects after specified days
    dynamic "expiration" {
      for_each = var.expire_objects_days > 0 ? [1] : []
      content {
        days = var.expire_objects_days
      }
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    # Clean up non-current versions
    dynamic "noncurrent_version_expiration" {
      for_each = var.enable_s3_versioning ? [1] : []
      content {
        noncurrent_days = 90
      }
    }
  }
}

# Configure S3 Intelligent Tiering for automatic cost optimization
resource "aws_s3_bucket_intelligent_tiering_configuration" "file_sharing" {
  count  = var.enable_intelligent_tiering ? 1 : 0
  bucket = aws_s3_bucket.file_sharing.id
  name   = "file_sharing_intelligent_tiering"

  # Apply to entire bucket
  filter {
    prefix = ""
  }

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

# Configure request metrics for monitoring
resource "aws_s3_bucket_metric" "file_sharing" {
  count  = var.enable_request_metrics ? 1 : 0
  bucket = aws_s3_bucket.file_sharing.id
  name   = "file_sharing_metrics"
}

# Configure CORS for Transfer Family Web App access
resource "aws_s3_bucket_cors_configuration" "file_sharing" {
  bucket = aws_s3_bucket.file_sharing.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]  # Will be updated with specific web app endpoint after creation
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

# =============================================================================
# IAM Roles for Transfer Family Web App and S3 Access Grants
# =============================================================================

# IAM role for S3 Access Grants location
resource "aws_iam_role" "access_grants_location" {
  name = "${local.resource_prefix}-access-grants-location-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "access-grants.s3.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-access-grants-location-role"
    Type = "ServiceRole"
  })
}

# IAM policy for S3 Access Grants location role
resource "aws_iam_role_policy" "access_grants_location" {
  name = "S3AccessGrantsLocationPolicy"
  role = aws_iam_role.access_grants_location.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          aws_s3_bucket.file_sharing.arn,
          "${aws_s3_bucket.file_sharing.arn}/*"
        ]
      }
    ]
  })
}

# IAM role for Transfer Family Web App
resource "aws_iam_role" "transfer_web_app" {
  name = "${local.resource_prefix}-transfer-web-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-transfer-web-app-role"
    Type = "ServiceRole"
  })
}

# IAM policy for Transfer Family Web App to integrate with S3 Access Grants
resource "aws_iam_role_policy" "transfer_web_app" {
  name = "TransferWebAppS3AccessGrantsPolicy"
  role = aws_iam_role.transfer_web_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetAccessGrant",
          "s3:GetDataAccess"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = local.region
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "identitystore:DescribeUser",
          "identitystore:DescribeGroup",
          "identitystore:ListGroupMemberships"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# IAM Identity Center Users and Groups
# =============================================================================

# Create demo users in IAM Identity Center
resource "aws_identitystore_user" "demo_users" {
  for_each = var.demo_users

  identity_store_id = local.identity_store_id
  display_name      = each.value.display_name
  user_name         = each.key

  name {
    given_name  = each.value.given_name
    family_name = each.value.family_name
  }

  emails {
    value   = each.value.email
    primary = true
    type    = "work"
  }

  timezone = "America/New_York"
  locale   = "en-US"

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-user-${each.key}"
    Type = "DemoUser"
    User = each.key
  })
}

# Create demo groups in IAM Identity Center
resource "aws_identitystore_group" "demo_groups" {
  for_each = var.demo_groups

  identity_store_id = local.identity_store_id
  display_name      = each.key
  description       = each.value.description

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-group-${each.key}"
    Type = "DemoGroup"
    Group = each.key
  })
}

# Create group memberships
resource "aws_identitystore_group_membership" "demo_memberships" {
  for_each = var.group_memberships

  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.demo_groups[each.value.group].group_id
  member_id         = aws_identitystore_user.demo_users[each.value.user].user_id
}

# =============================================================================
# S3 Access Grants Configuration
# =============================================================================

# Create S3 Access Grants instance with IAM Identity Center integration
resource "aws_s3control_access_grants_instance" "main" {
  identity_center_arn = local.identity_center_arn

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-access-grants-instance"
    Type = "AccessGrantsInstance"
  })
}

# Register S3 location for access grants
resource "aws_s3control_access_grants_location" "file_sharing" {
  depends_on = [aws_s3control_access_grants_instance.main]

  iam_role_arn   = aws_iam_role.access_grants_location.arn
  location_scope = "s3://${aws_s3_bucket.file_sharing.bucket}/*"

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-access-grants-location"
    Type = "AccessGrantsLocation"
    Bucket = aws_s3_bucket.file_sharing.bucket
  })
}

# Create access grants for individual users
resource "aws_s3control_access_grant" "user_grants" {
  for_each = var.user_access_grants

  access_grants_location_id = aws_s3control_access_grants_location.file_sharing.access_grants_location_id
  permission               = each.value.permission

  grantee {
    grantee_type       = "DIRECTORY_USER"
    grantee_identifier = "${local.identity_store_id}:user/${aws_identitystore_user.demo_users[each.key].user_id}"
  }

  access_grants_location_configuration {
    s3_sub_prefix = each.value.prefix
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-user-grant-${each.key}"
    Type = "UserAccessGrant"
    User = each.key
    Permission = each.value.permission
  })
}

# Create access grants for groups
resource "aws_s3control_access_grant" "group_grants" {
  for_each = var.group_access_grants

  access_grants_location_id = aws_s3control_access_grants_location.file_sharing.access_grants_location_id
  permission               = each.value.permission

  grantee {
    grantee_type       = "DIRECTORY_GROUP"
    grantee_identifier = "${local.identity_store_id}:group/${aws_identitystore_group.demo_groups[each.key].group_id}"
  }

  access_grants_location_configuration {
    s3_sub_prefix = each.value.prefix
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-group-grant-${each.key}"
    Type = "GroupAccessGrant"
    Group = each.key
    Permission = each.value.permission
  })
}

# =============================================================================
# CloudWatch Logging for Monitoring
# =============================================================================

# CloudWatch log group for file sharing activities
resource "aws_cloudwatch_log_group" "file_sharing" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  name              = "/aws/transfer/file-sharing/${local.resource_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-file-sharing-logs"
    Type = "LogGroup"
  })
}

# CloudWatch log stream for Transfer Family Web App
resource "aws_cloudwatch_log_stream" "transfer_web_app" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  name           = "transfer-web-app-stream"
  log_group_name = aws_cloudwatch_log_group.file_sharing[0].name
}

# =============================================================================
# CloudTrail for Audit Logging
# =============================================================================

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  count         = var.enable_cloudtrail ? 1 : 0
  bucket        = "${local.bucket_name}-cloudtrail-logs"
  force_destroy = var.environment == "dev" ? true : false

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-cloudtrail-logs"
    Type = "AuditLogStorage"
  })
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
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.resource_prefix}-file-sharing-trail"
          }
        }
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
            "AWS:SourceArn" = "arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.resource_prefix}-file-sharing-trail"
          }
        }
      }
    ]
  })
}

# CloudTrail for auditing file sharing activities
resource "aws_cloudtrail" "file_sharing" {
  count = var.enable_cloudtrail ? 1 : 0

  name           = "${local.resource_prefix}-file-sharing-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs[0].bucket

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.file_sharing.arn}/*"]
    }

    data_resource {
      type   = "AWS::S3::Bucket"
      values = [aws_s3_bucket.file_sharing.arn]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-file-sharing-trail"
    Type = "AuditTrail"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}

# =============================================================================
# CloudWatch Alarms for Monitoring
# =============================================================================

# Alarm for high number of failed access attempts
resource "aws_cloudwatch_metric_alarm" "failed_access_attempts" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  alarm_name          = "${local.resource_prefix}-failed-access-attempts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors failed access attempts to the file sharing bucket"

  dimensions = {
    BucketName = aws_s3_bucket.file_sharing.bucket
  }

  alarm_actions = []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-failed-access-alarm"
    Type = "SecurityAlarm"
  })
}

# Alarm for unusual data transfer volumes
resource "aws_cloudwatch_metric_alarm" "high_data_transfer" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  alarm_name          = "${local.resource_prefix}-high-data-transfer"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BytesDownloaded"
  namespace           = "AWS/S3"
  period              = "3600"
  statistic           = "Sum"
  threshold           = "10737418240" # 10 GB
  alarm_description   = "This metric monitors unusually high data transfer from the file sharing bucket"

  dimensions = {
    BucketName = aws_s3_bucket.file_sharing.bucket
  }

  alarm_actions = []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-high-transfer-alarm"
    Type = "UsageAlarm"
  })
}

# =============================================================================
# NOTE: Transfer Family Web App Manual Configuration Required
# =============================================================================

# Transfer Family Web Apps are not yet supported in Terraform as of AWS Provider v5.x
# The following resources need to be created manually using AWS CLI or Console:

# 1. Create Transfer Family Web App
# aws transfer create-web-app \
#   --identity-provider-details '{
#     "IdentityCenterConfig": {
#       "InstanceArn": "IDENTITY_CENTER_ARN",
#       "Role": "TRANSFER_WEB_APP_ROLE_ARN"
#     }
#   }' \
#   --tags 'Key=Name,Value=file-sharing-web-app'

# 2. Assign users to the web app
# aws transfer create-web-app-assignment \
#   --web-app-id WEB_APP_ID \
#   --grantee '{
#     "Type": "USER",
#     "Identifier": "USER_ID"
#   }'

# 3. Update CORS configuration with the actual web app endpoint
# The CORS configuration above uses wildcard origins and will need to be updated
# with the specific Transfer Family Web App endpoint after creation

# This configuration provides all the foundation infrastructure needed for
# Transfer Family Web Apps. Once Terraform support is added, this file can be
# updated to include the aws_transfer_web_app and aws_transfer_web_app_assignment
# resources directly.