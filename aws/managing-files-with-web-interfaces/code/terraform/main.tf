# Main Terraform configuration for AWS Transfer Family Web Apps self-service file management

# Generate random suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get existing IAM Identity Center instance
data "aws_ssoadmin_instances" "existing" {}

locals {
  # Resource naming
  bucket_name = "${var.project_name}-demo-${random_string.suffix.result}${var.bucket_name_suffix}"
  webapp_name = "${var.project_name}-webapp-${random_string.suffix.result}"
  
  # IAM Identity Center instance details
  identity_center_instance_arn = try(data.aws_ssoadmin_instances.existing.arns[0], null)
  identity_store_id           = try(data.aws_ssoadmin_instances.existing.identity_store_ids[0], null)
  
  # Merged tags
  common_tags = merge(var.tags, {
    Project     = "Self-Service File Management"
    Environment = var.environment
  })
}

# Validate that IAM Identity Center is available
resource "null_resource" "identity_center_validation" {
  count = local.identity_center_instance_arn != null ? 0 : 1
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "ERROR: IAM Identity Center is not enabled in this AWS account."
      echo "Please enable IAM Identity Center before running this Terraform configuration."
      exit 1
    EOT
  }
}

#------------------------------------------------------------------------------
# S3 BUCKET AND CONFIGURATION
#------------------------------------------------------------------------------

# S3 bucket for file storage
resource "aws_s3_bucket" "file_storage" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "file_storage" {
  count      = var.s3_lifecycle_enabled ? 1 : 0
  depends_on = [aws_s3_bucket_versioning.file_storage]

  bucket = aws_s3_bucket.file_storage.id

  rule {
    id     = "user_files_lifecycle"
    status = "Enabled"

    filter {
      prefix = "user-files/"
    }

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_transition_days * 3
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

#------------------------------------------------------------------------------
# IAM ROLES FOR S3 ACCESS GRANTS
#------------------------------------------------------------------------------

# IAM role for S3 Access Grants
resource "aws_iam_role" "s3_access_grants" {
  name = "S3AccessGrantsRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "S3AccessGrantsRole-${random_string.suffix.result}"
  })
}

# Attach S3 Full Access policy to the role
resource "aws_iam_role_policy_attachment" "s3_access_grants" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.s3_access_grants.name
}

# Identity Bearer Role for Transfer Family
resource "aws_iam_role" "transfer_identity_bearer" {
  name = "TransferIdentityBearerRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "TransferIdentityBearerRole-${random_string.suffix.result}"
  })
}

# Policy for Identity Bearer Role
resource "aws_iam_role_policy" "transfer_identity_bearer" {
  name = "S3AccessGrantsPolicy"
  role = aws_iam_role.transfer_identity_bearer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetDataAccess"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sso:DescribeInstance"
        ]
        Resource = "*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# S3 ACCESS GRANTS CONFIGURATION
#------------------------------------------------------------------------------

# S3 Access Grants Instance
resource "aws_s3control_access_grants_instance" "main" {
  identity_center_arn = local.identity_center_instance_arn

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-grants-${random_string.suffix.result}"
    Purpose = "FileManagement"
  })

  depends_on = [null_resource.identity_center_validation]
}

# S3 Access Grants Location
resource "aws_s3control_access_grants_location" "main" {
  access_grants_instance_arn = aws_s3control_access_grants_instance.main.arn
  location_scope            = "s3://${aws_s3_bucket.file_storage.id}/*"
  iam_role_arn              = aws_iam_role.s3_access_grants.arn

  tags = merge(local.common_tags, {
    Name = "FileManagementLocation"
  })
}

#------------------------------------------------------------------------------
# IAM IDENTITY CENTER TEST USER
#------------------------------------------------------------------------------

# Test user in IAM Identity Center
resource "aws_identitystore_user" "test_user" {
  count             = var.create_test_user ? 1 : 0
  identity_store_id = local.identity_store_id

  display_name = "Test User"
  user_name    = "testuser"

  name {
    family_name = "User"
    given_name  = "Test"
  }

  emails {
    value   = var.test_user_email
    type    = "work"
    primary = true
  }

  depends_on = [null_resource.identity_center_validation]
}

# Access grant for test user
resource "aws_s3control_access_grant" "test_user" {
  count                             = var.create_test_user ? 1 : 0
  access_grants_instance_arn        = aws_s3control_access_grants_instance.main.arn
  access_grants_location_id         = aws_s3control_access_grants_location.main.access_grants_location_id
  permission                        = var.access_grants_permission
  
  access_grants_location_configuration {
    s3_sub_prefix = var.access_grants_location_scope
  }

  grantee {
    grantee_type       = "IAM_IDENTITY_CENTER_USER"
    grantee_identifier = aws_identitystore_user.test_user[0].user_id
  }

  tags = merge(local.common_tags, {
    Name = "TestUserGrant"
  })
}

#------------------------------------------------------------------------------
# VPC AND NETWORKING
#------------------------------------------------------------------------------

# Get default VPC if requested
data "aws_vpc" "default" {
  count   = var.use_default_vpc ? 1 : 0
  default = true
}

# Get default subnets if using default VPC
data "aws_subnets" "default" {
  count = var.use_default_vpc ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  # VPC and subnet configuration
  vpc_id     = var.use_default_vpc ? data.aws_vpc.default[0].id : var.vpc_id
  subnet_ids = var.use_default_vpc ? data.aws_subnets.default[0].ids : var.subnet_ids
}

#------------------------------------------------------------------------------
# AWS TRANSFER FAMILY WEB APP
#------------------------------------------------------------------------------

# Transfer Family Web App
resource "aws_transfer_web_app" "main" {
  identity_provider_type = "SERVICE_MANAGED"

  identity_provider_details {
    identity_center_config {
      instance_arn = local.identity_center_instance_arn
      role         = aws_iam_role.transfer_identity_bearer.arn
    }
  }

  access_endpoint {
    type       = "VPC"
    vpc_id     = local.vpc_id
    subnet_ids = slice(local.subnet_ids, 0, min(length(local.subnet_ids), 1))
  }

  tags = merge(local.common_tags, {
    Name        = local.webapp_name
    Environment = var.environment
  })

  depends_on = [
    aws_s3control_access_grants_instance.main,
    aws_iam_role_policy.transfer_identity_bearer
  ]
}

# Configure web app branding
resource "aws_transfer_web_app" "branding_update" {
  web_app_id             = aws_transfer_web_app.main.web_app_id
  identity_provider_type = aws_transfer_web_app.main.identity_provider_type

  identity_provider_details {
    identity_center_config {
      instance_arn = local.identity_center_instance_arn
      role         = aws_iam_role.transfer_identity_bearer.arn
    }
  }

  access_endpoint {
    type       = "VPC"
    vpc_id     = local.vpc_id
    subnet_ids = slice(local.subnet_ids, 0, min(length(local.subnet_ids), 1))
  }

  branding {
    title       = var.webapp_branding.title
    description = var.webapp_branding.description
    logo_url    = var.webapp_branding.logo_url
    favicon_url = var.webapp_branding.favicon_url
  }

  tags = merge(local.common_tags, {
    Name        = local.webapp_name
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# SAMPLE FILES (OPTIONAL)
#------------------------------------------------------------------------------

# Sample README file
resource "aws_s3_object" "sample_readme" {
  count  = var.create_sample_files ? 1 : 0
  bucket = aws_s3_bucket.file_storage.id
  key    = "user-files/documents/README.txt"
  
  content = <<-EOT
Welcome to the Secure File Management Portal!

This system provides a secure, easy-to-use interface for managing your files.

Getting Started:
1. Navigate through folders using the web interface
2. Upload files by dragging and dropping or using the upload button
3. Download files by clicking on them
4. Create new folders using the "New Folder" button

For support, contact your IT administrator.
EOT

  content_type = "text/plain"

  tags = merge(local.common_tags, {
    Name = "Sample README"
  })
}

# Sample document file
resource "aws_s3_object" "sample_document" {
  count  = var.create_sample_files ? 1 : 0
  bucket = aws_s3_bucket.file_storage.id
  key    = "user-files/documents/sample-document.txt"
  
  content = <<-EOT
This is a sample document to demonstrate file management capabilities.
You can upload, download, and manage files like this one through the web interface.
EOT

  content_type = "text/plain"

  tags = merge(local.common_tags, {
    Name = "Sample Document"
  })
}

# Sample shared file
resource "aws_s3_object" "sample_shared" {
  count  = var.create_sample_files ? 1 : 0
  bucket = aws_s3_bucket.file_storage.id
  key    = "user-files/shared/team-resources.txt"
  
  content = <<-EOT
This folder contains shared resources for the team.
All team members have access to files in this location.
EOT

  content_type = "text/plain"

  tags = merge(local.common_tags, {
    Name = "Sample Shared Resource"
  })
}

#------------------------------------------------------------------------------
# CLOUDTRAIL FOR AUDITING (OPTIONAL)
#------------------------------------------------------------------------------

# CloudTrail S3 bucket for logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = "${local.bucket_name}-cloudtrail-logs"

  tags = merge(local.common_tags, {
    Name = "${local.bucket_name}-cloudtrail-logs"
  })
}

# CloudTrail bucket policy
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
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
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-trail"
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
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-trail"
          }
        }
      }
    ]
  })
}

# CloudTrail for S3 API logging
resource "aws_cloudtrail" "s3_logging" {
  count                         = var.enable_cloudtrail_logging ? 1 : 0
  name                          = "${var.project_name}-trail"
  s3_bucket_name               = aws_s3_bucket.cloudtrail_logs[0].id
  include_global_service_events = false

  event_selector {
    read_write_type                 = "All"
    include_management_events       = false
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.file_storage.arn}/*"]
    }

    data_resource {
      type   = "AWS::S3::Bucket"
      values = [aws_s3_bucket.file_storage.arn]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-trail"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs[0]]
}