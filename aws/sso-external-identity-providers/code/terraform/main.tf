# AWS Single Sign-On with External Identity Providers
# This Terraform configuration sets up AWS IAM Identity Center (SSO) with external identity provider integration

# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Data source for AWS Organizations to get account information
data "aws_organizations_organization" "current" {
  count = 1
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# ==============================================================================
# IAM Identity Center Instance and Configuration
# ==============================================================================

# Data source to get the existing IAM Identity Center instance
# Note: IAM Identity Center must be enabled manually in the AWS Console first
data "aws_ssoadmin_instances" "current" {}

locals {
  # Extract the instance ARN and identity store ID
  sso_instance_arn   = length(data.aws_ssoadmin_instances.current.arns) > 0 ? data.aws_ssoadmin_instances.current.arns[0] : null
  identity_store_id  = length(data.aws_ssoadmin_instances.current.identity_store_ids) > 0 ? data.aws_ssoadmin_instances.current.identity_store_ids[0] : null
  
  # Current account ID for assignments
  current_account_id = data.aws_caller_identity.current.account_id
  
  # Generate unique suffix for resources
  suffix = lower(random_id.suffix.hex)
  
  # CloudTrail bucket name
  cloudtrail_bucket_name = var.cloudtrail_s3_bucket_name != "" ? var.cloudtrail_s3_bucket_name : "sso-cloudtrail-${local.suffix}"
}

# ==============================================================================
# Permission Sets
# ==============================================================================

# Create permission sets based on the configuration
resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.permission_sets

  name             = each.key
  description      = each.value.description
  instance_arn     = local.sso_instance_arn
  session_duration = each.value.session_duration
  relay_state      = each.value.relay_state

  tags = merge(var.tags, {
    Name = each.key
    Type = "PermissionSet"
  })
}

# Attach managed policies to permission sets
resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = {
    for combo in flatten([
      for ps_key, ps_config in var.permission_sets : [
        for policy_arn in ps_config.managed_policy_arns : {
          permission_set_key = ps_key
          policy_arn        = policy_arn
          unique_key        = "${ps_key}-${replace(policy_arn, "/[^a-zA-Z0-9]/", "-")}"
        }
      ]
    ]) : combo.unique_key => combo
  }

  instance_arn       = local.sso_instance_arn
  managed_policy_arn = each.value.policy_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set_key].arn
}

# Create custom inline policies for permission sets that have them
resource "aws_ssoadmin_permission_set_inline_policy" "this" {
  for_each = {
    for ps_key, ps_config in var.permission_sets : ps_key => ps_config
    if ps_config.inline_policy != null
  }

  inline_policy      = each.value.inline_policy
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
}

# Example custom inline policy for S3 access (demonstration)
resource "aws_ssoadmin_permission_set_inline_policy" "developer_s3_policy" {
  count = contains(keys(var.permission_sets), "DeveloperAccess") ? 1 : 0

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this["DeveloperAccess"].arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::company-data-${local.suffix}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::company-data-${local.suffix}"
      }
    ]
  })
}

# ==============================================================================
# External Identity Provider Configuration (Optional)
# ==============================================================================

# External identity provider configuration (SAML)
resource "aws_ssoadmin_external_identity_provider" "this" {
  count = var.enable_external_idp && var.saml_metadata_document != "" ? 1 : 0

  instance_arn = local.sso_instance_arn
  
  saml {
    metadata_document = var.saml_metadata_document
    
    # Attribute mapping for SAML attributes
    attribute_mappings = {
      "email"    = "${path:enterprise.email}"
      "name"     = "${path:enterprise.displayName}"
      "username" = "${path:enterprise.userName}"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.identity_provider_name}-SAML"
    Type = "ExternalIdentityProvider"
  })
}

# Access control attribute configuration for ABAC
resource "aws_ssoadmin_instance_access_control_attributes" "this" {
  count = var.enable_external_idp ? 1 : 0

  instance_arn = local.sso_instance_arn

  dynamic "attribute" {
    for_each = var.attribute_mappings
    content {
      key = attribute.value.attribute_key
      value {
        source = attribute.value.attribute_source
      }
    }
  }
}

# ==============================================================================
# Local Identity Store Management (for demonstration/testing)
# ==============================================================================

# Create test users in the identity store
resource "aws_identitystore_user" "test_users" {
  for_each = var.test_users

  identity_store_id = local.identity_store_id
  
  user_name    = each.key
  display_name = each.value.display_name
  
  name {
    given_name  = each.value.given_name
    family_name = each.value.family_name
  }
  
  emails {
    value   = each.value.email
    type    = "work"
    primary = true
  }

  # Add a small delay to ensure proper creation order
  depends_on = [time_sleep.wait_for_sso_instance]
}

# Create test groups in the identity store
resource "aws_identitystore_group" "test_groups" {
  for_each = var.test_groups

  identity_store_id = local.identity_store_id
  display_name      = each.value.display_name
  description       = each.value.description

  # Add a small delay to ensure proper creation order
  depends_on = [time_sleep.wait_for_sso_instance]
}

# Add users to groups
resource "aws_identitystore_group_membership" "test_group_memberships" {
  for_each = {
    for combo in flatten([
      for group_key, group_config in var.test_groups : [
        for member in group_config.members : {
          group_key = group_key
          user_key  = member
          unique_key = "${group_key}-${member}"
        }
      ]
    ]) : combo.unique_key => combo
  }

  identity_store_id = local.identity_store_id
  group_id         = aws_identitystore_group.test_groups[each.value.group_key].group_id
  member_id        = aws_identitystore_user.test_users[each.value.user_key].user_id
}

# ==============================================================================
# Account Assignments
# ==============================================================================

# Account assignments for users and groups
resource "aws_ssoadmin_account_assignment" "this" {
  for_each = var.account_assignments

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  
  # Use current account if not specified
  target_id   = each.value.account_id != "" ? each.value.account_id : local.current_account_id
  target_type = "AWS_ACCOUNT"
  
  principal_type = each.value.principal_type
  principal_id = each.value.principal_type == "USER" ? 
    aws_identitystore_user.test_users[each.value.principal_name].user_id :
    aws_identitystore_group.test_groups[each.value.principal_name].group_id

  depends_on = [
    aws_identitystore_user.test_users,
    aws_identitystore_group.test_groups,
    aws_identitystore_group_membership.test_group_memberships
  ]
}

# ==============================================================================
# CloudTrail for SSO Event Logging (Optional)
# ==============================================================================

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail" {
  count = var.enable_cloudtrail_logging ? 1 : 0

  bucket        = local.cloudtrail_bucket_name
  force_destroy = true

  tags = merge(var.tags, {
    Name    = local.cloudtrail_bucket_name
    Purpose = "SSO-CloudTrail-Logs"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "cloudtrail" {
  count = var.enable_cloudtrail_logging ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count = var.enable_cloudtrail_logging ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  count = var.enable_cloudtrail_logging ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudTrail bucket policy
resource "aws_s3_bucket_policy" "cloudtrail" {
  count = var.enable_cloudtrail_logging ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

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
        Resource = aws_s3_bucket.cloudtrail[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/sso-audit-trail-${local.suffix}"
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
        Resource = "${aws_s3_bucket.cloudtrail[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/sso-audit-trail-${local.suffix}"
          }
        }
      }
    ]
  })
}

# CloudTrail for SSO event logging
resource "aws_cloudtrail" "sso_audit" {
  count = var.enable_cloudtrail_logging ? 1 : 0

  name           = "sso-audit-trail-${local.suffix}"
  s3_bucket_name = aws_s3_bucket.cloudtrail[0].bucket

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.cloudtrail[0].arn}/*"]
    }
  }

  # Include SSO events
  advanced_event_selector {
    name = "SSO Events"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }

    field_selector {
      field  = "eventName"
      equals = [
        "AssumeRoleWithSAML",
        "Login",
        "Logout",
        "CreatePermissionSet",
        "UpdatePermissionSet",
        "DeletePermissionSet"
      ]
    }
  }

  tags = merge(var.tags, {
    Name    = "sso-audit-trail-${local.suffix}"
    Purpose = "SSO-Event-Logging"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# ==============================================================================
# Utility Resources
# ==============================================================================

# Time delay to ensure SSO instance is ready
resource "time_sleep" "wait_for_sso_instance" {
  create_duration = "30s"

  triggers = {
    sso_instance_arn = local.sso_instance_arn
  }
}