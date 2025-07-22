# Fine-Grained Access Control with IAM Policies and Conditions
# This configuration implements advanced IAM access controls using conditional policies

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  # Construct resource names with random suffix
  resource_prefix = "${var.project_name}-${random_string.suffix.result}"
  bucket_name     = "${local.resource_prefix}-test-bucket"
  log_group_name  = "/aws/lambda/${local.resource_prefix}"
  
  # Convert business hours to UTC format for policy conditions
  business_hours_start_utc = "${var.business_hours_start}Z"
  business_hours_end_utc   = "${var.business_hours_end}Z"
  
  # Common tags for all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "fine-grained-access-control-iam-policies-conditions"
      ManagedBy   = "Terraform"
    },
    var.resource_tags
  )
}

# ========================================
# S3 Bucket for Testing
# ========================================

# S3 bucket for testing access control policies
resource "aws_s3_bucket" "test_bucket" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    ResourceType = "Storage"
    Purpose      = "Policy Testing"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "test_bucket_versioning" {
  bucket = aws_s3_bucket.test_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "test_bucket_encryption" {
  bucket = aws_s3_bucket.test_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.s3_encryption_type
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "test_bucket_pab" {
  bucket = aws_s3_bucket.test_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ========================================
# CloudWatch Log Group for Testing
# ========================================

# CloudWatch log group for testing logging policies
resource "aws_cloudwatch_log_group" "test_log_group" {
  name              = local.log_group_name
  retention_in_days = 7

  tags = merge(local.common_tags, {
    ResourceType = "Logging"
    Purpose      = "Policy Testing"
  })
}

# ========================================
# IAM Policy Documents
# ========================================

# Business hours access policy document
data "aws_iam_policy_document" "business_hours_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    
    resources = [
      aws_s3_bucket.test_bucket.arn,
      "${aws_s3_bucket.test_bucket.arn}/*"
    ]
    
    condition {
      test     = "DateGreaterThan"
      variable = "aws:CurrentTime"
      values   = [local.business_hours_start_utc]
    }
    
    condition {
      test     = "DateLessThan"
      variable = "aws:CurrentTime"
      values   = [local.business_hours_end_utc]
    }
  }
}

# IP-based access control policy document
data "aws_iam_policy_document" "ip_restriction_policy" {
  # Allow CloudWatch Logs access from specific IP ranges
  statement {
    effect = "Allow"
    
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    
    resources = [
      "${aws_cloudwatch_log_group.test_log_group.arn}*"
    ]
    
    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = var.allowed_ip_ranges
    }
  }
  
  # Deny all actions from unauthorized IP ranges
  statement {
    effect = "Deny"
    
    actions = ["*"]
    
    resources = ["*"]
    
    condition {
      test     = "Bool"
      variable = "aws:ViaAWSService"
      values   = ["false"]
    }
    
    condition {
      test     = "NotIpAddress"
      variable = "aws:SourceIp"
      values   = var.allowed_ip_ranges
    }
  }
}

# Tag-based access control policy document
data "aws_iam_policy_document" "tag_based_policy" {
  # Allow access to objects with matching department tags
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    
    resources = ["${aws_s3_bucket.test_bucket.arn}/*"]
    
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/Department"
      values   = ["$${s3:ExistingObjectTag/Department}"]
    }
  }
  
  # Allow access to shared folder for all users
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    
    resources = ["${aws_s3_bucket.test_bucket.arn}/shared/*"]
  }
  
  # Allow listing with prefix restrictions based on department
  statement {
    effect = "Allow"
    
    actions = ["s3:ListBucket"]
    
    resources = [aws_s3_bucket.test_bucket.arn]
    
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "shared/*",
        "$${aws:PrincipalTag/Department}/*"
      ]
    }
  }
}

# MFA-required policy document
data "aws_iam_policy_document" "mfa_required_policy" {
  # Allow read operations without MFA
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    
    resources = [
      aws_s3_bucket.test_bucket.arn,
      "${aws_s3_bucket.test_bucket.arn}/*"
    ]
  }
  
  # Require MFA for write operations
  statement {
    effect = "Allow"
    
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:PutObjectAcl"
    ]
    
    resources = ["${aws_s3_bucket.test_bucket.arn}/*"]
    
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
    
    condition {
      test     = "NumericLessThan"
      variable = "aws:MultiFactorAuthAge"
      values   = [tostring(var.mfa_max_age_seconds)]
    }
  }
}

# Session-based access control policy document
data "aws_iam_policy_document" "session_policy" {
  # Allow CloudWatch Logs operations with session constraints
  statement {
    effect = "Allow"
    
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    
    resources = ["${aws_cloudwatch_log_group.test_log_group.arn}*"]
    
    condition {
      test     = "StringEquals"
      variable = "aws:userid"
      values   = ["$${aws:userid}"]
    }
    
    condition {
      test     = "StringLike"
      variable = "aws:rolename"
      values   = ["${local.resource_prefix}*"]
    }
    
    condition {
      test     = "NumericLessThan"
      variable = "aws:TokenIssueTime"
      values   = ["$${aws:CurrentTime}"]
    }
  }
  
  # Allow session token creation with duration limits
  statement {
    effect = "Allow"
    
    actions = ["sts:GetSessionToken"]
    
    resources = ["*"]
    
    condition {
      test     = "NumericLessThan"
      variable = "aws:RequestedDuration"
      values   = [tostring(var.session_duration_seconds)]
    }
  }
}

# ========================================
# IAM Policies
# ========================================

# Business hours access policy
resource "aws_iam_policy" "business_hours_policy" {
  name        = "${local.resource_prefix}-business-hours-policy"
  description = "S3 access restricted to business hours"
  policy      = data.aws_iam_policy_document.business_hours_policy.json

  tags = merge(local.common_tags, {
    PolicyType = "Temporal Access Control"
  })
}

# IP-based access control policy
resource "aws_iam_policy" "ip_restriction_policy" {
  name        = "${local.resource_prefix}-ip-restriction-policy"
  description = "CloudWatch Logs access from specific IP ranges only"
  policy      = data.aws_iam_policy_document.ip_restriction_policy.json

  tags = merge(local.common_tags, {
    PolicyType = "Network Access Control"
  })
}

# Tag-based access control policy
resource "aws_iam_policy" "tag_based_policy" {
  name        = "${local.resource_prefix}-tag-based-policy"
  description = "S3 access based on user and resource tags"
  policy      = data.aws_iam_policy_document.tag_based_policy.json

  tags = merge(local.common_tags, {
    PolicyType = "Attribute-Based Access Control"
  })
}

# MFA-required policy
resource "aws_iam_policy" "mfa_required_policy" {
  name        = "${local.resource_prefix}-mfa-required-policy"
  description = "S3 write operations require MFA authentication"
  policy      = data.aws_iam_policy_document.mfa_required_policy.json

  tags = merge(local.common_tags, {
    PolicyType = "Multi-Factor Authentication"
  })
}

# Session-based access control policy
resource "aws_iam_policy" "session_policy" {
  name        = "${local.resource_prefix}-session-policy"
  description = "Session-based access control with duration limits"
  policy      = data.aws_iam_policy_document.session_policy.json

  tags = merge(local.common_tags, {
    PolicyType = "Session Access Control"
  })
}

# ========================================
# S3 Bucket Policy (Resource-Based)
# ========================================

# Resource-based policy for S3 bucket
data "aws_iam_policy_document" "bucket_policy" {
  # Allow access from test role with encryption requirements
  statement {
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = var.create_test_resources ? [aws_iam_role.test_role[0].arn] : []
    }
    
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    
    resources = ["${aws_s3_bucket.test_bucket.arn}/*"]
    
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = [var.s3_encryption_type]
    }
    
    condition {
      test     = "StringLike"
      variable = "s3:x-amz-meta-project"
      values   = ["${local.resource_prefix}*"]
    }
  }
  
  # Deny insecure transport
  statement {
    effect = "Deny"
    
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    
    actions = ["s3:*"]
    
    resources = [
      aws_s3_bucket.test_bucket.arn,
      "${aws_s3_bucket.test_bucket.arn}/*"
    ]
    
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# Apply bucket policy
resource "aws_s3_bucket_policy" "test_bucket_policy" {
  bucket = aws_s3_bucket.test_bucket.id
  policy = data.aws_iam_policy_document.bucket_policy.json
  
  depends_on = [aws_s3_bucket_public_access_block.test_bucket_pab]
}

# ========================================
# Test IAM User and Role (Optional)
# ========================================

# Test user for policy validation
resource "aws_iam_user" "test_user" {
  count = var.create_test_resources ? 1 : 0
  name  = "${local.resource_prefix}-test-user"

  tags = merge(local.common_tags, {
    Department   = var.test_department
    Project      = local.resource_prefix
    ResourceType = "Test User"
  })
}

# Test user tags
resource "aws_iam_user_policy_attachment" "test_user_tag_policy" {
  count      = var.create_test_resources ? 1 : 0
  user       = aws_iam_user.test_user[0].name
  policy_arn = aws_iam_policy.tag_based_policy.arn
}

# Trust policy for test role
data "aws_iam_policy_document" "test_role_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = var.create_test_resources ? [aws_iam_user.test_user[0].arn] : []
    }
    
    actions = ["sts:AssumeRole"]
    
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.name]
    }
    
    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = var.allowed_ip_ranges
    }
  }
}

# Test role with conditional trust policy
resource "aws_iam_role" "test_role" {
  count               = var.create_test_resources ? 1 : 0
  name                = "${local.resource_prefix}-test-role"
  description         = "Test role with conditional access"
  assume_role_policy  = data.aws_iam_policy_document.test_role_trust_policy.json
  max_session_duration = var.session_duration_seconds

  tags = merge(local.common_tags, {
    Department   = var.test_department
    Environment  = "Test"
    ResourceType = "Test Role"
  })
}

# Attach business hours policy to test role
resource "aws_iam_role_policy_attachment" "test_role_business_hours" {
  count      = var.create_test_resources ? 1 : 0
  role       = aws_iam_role.test_role[0].name
  policy_arn = aws_iam_policy.business_hours_policy.arn
}

# ========================================
# Sample S3 Objects for Testing
# ========================================

# Sample object for Engineering department
resource "aws_s3_object" "test_object_engineering" {
  count  = var.create_test_resources ? 1 : 0
  bucket = aws_s3_bucket.test_bucket.id
  key    = "Engineering/test-file.txt"
  content = "Test content for engineering department"
  
  server_side_encryption = var.s3_encryption_type
  
  metadata = {
    project = "${local.resource_prefix}-test"
  }
  
  tags = {
    Department = var.test_department
    Project    = local.resource_prefix
  }
}

# Sample shared object
resource "aws_s3_object" "test_object_shared" {
  count  = var.create_test_resources ? 1 : 0
  bucket = aws_s3_bucket.test_bucket.id
  key    = "shared/readme.txt"
  content = "This is a shared file accessible by all authorized users"
  
  server_side_encryption = var.s3_encryption_type
  
  metadata = {
    project = "${local.resource_prefix}-shared"
  }
  
  tags = {
    AccessLevel = "Shared"
    Project     = local.resource_prefix
  }
}

# ========================================
# CloudTrail for Audit Logging (Optional)
# ========================================

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_bucket" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = "${local.resource_prefix}-cloudtrail-logs"

  tags = merge(local.common_tags, {
    ResourceType = "Audit Logging"
    Purpose      = "CloudTrail Logs"
  })
}

# CloudTrail bucket policy
data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  count = var.enable_cloudtrail_logging ? 1 : 0
  
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    
    actions = ["s3:PutObject"]
    
    resources = ["${aws_s3_bucket.cloudtrail_bucket[0].arn}/*"]
    
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
  
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    
    actions = ["s3:GetBucketAcl"]
    
    resources = [aws_s3_bucket.cloudtrail_bucket[0].arn]
  }
}

# Apply CloudTrail bucket policy
resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_bucket[0].id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy[0].json
}

# CloudTrail for API logging
resource "aws_cloudtrail" "access_control_trail" {
  count          = var.enable_cloudtrail_logging ? 1 : 0
  name           = "${local.resource_prefix}-access-control-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail_bucket[0].id
  
  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []
    
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.test_bucket.arn}/*"]
    }
  }

  tags = merge(local.common_tags, {
    ResourceType = "Audit Trail"
    Purpose      = "Access Control Monitoring"
  })
  
  depends_on = [aws_s3_bucket_policy.cloudtrail_bucket_policy]
}