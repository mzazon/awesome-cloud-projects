# Amazon Q Developer AI Code Assistant Infrastructure
# This Terraform configuration sets up the necessary IAM resources and configurations
# to support Amazon Q Developer usage within an organization

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Amazon Q Developer"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CreatedDate = timestamp()
    }
  }
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# IAM role for Amazon Q Developer administrative access
resource "aws_iam_role" "amazon_q_admin_role" {
  count = var.create_admin_role ? 1 : 0
  
  name        = "${var.resource_prefix}-amazon-q-admin-role"
  description = "Administrative role for Amazon Q Developer management"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.resource_prefix}-amazon-q-admin-role"
    Description = "Administrative role for Amazon Q Developer"
  }
}

# IAM policy for Amazon Q Developer administrative access
resource "aws_iam_policy" "amazon_q_admin_policy" {
  count = var.create_admin_role ? 1 : 0
  
  name        = "${var.resource_prefix}-amazon-q-admin-policy"
  description = "Policy for Amazon Q Developer administrative access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "q:*",
          "codewhisperer:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:ListPolicies",
          "iam:GetRole",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "organizations:DescribeOrganization",
          "organizations:ListAccounts"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.resource_prefix}-amazon-q-admin-policy"
    Description = "Administrative policy for Amazon Q Developer"
  }
}

# Attach the admin policy to the admin role
resource "aws_iam_role_policy_attachment" "amazon_q_admin_attachment" {
  count = var.create_admin_role ? 1 : 0
  
  role       = aws_iam_role.amazon_q_admin_role[0].name
  policy_arn = aws_iam_policy.amazon_q_admin_policy[0].arn
}

# IAM role for Amazon Q Developer users
resource "aws_iam_role" "amazon_q_user_role" {
  count = var.create_user_role ? 1 : 0
  
  name        = "${var.resource_prefix}-amazon-q-user-role"
  description = "User role for Amazon Q Developer access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = var.trusted_user_arns
        }
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.resource_prefix}-amazon-q-user-role"
    Description = "User role for Amazon Q Developer access"
  }
}

# IAM policy for Amazon Q Developer user access
resource "aws_iam_policy" "amazon_q_user_policy" {
  count = var.create_user_role ? 1 : 0
  
  name        = "${var.resource_prefix}-amazon-q-user-policy"
  description = "Policy for Amazon Q Developer user access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "q:StartConversation",
          "q:SendMessage",
          "q:GetConversation",
          "q:ListConversations"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codewhisperer:GenerateRecommendations",
          "codewhisperer:GetCodeScan",
          "codewhisperer:CreateCodeScan"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.resource_prefix}-amazon-q-user-policy"
    Description = "User policy for Amazon Q Developer access"
  }
}

# Attach the user policy to the user role
resource "aws_iam_role_policy_attachment" "amazon_q_user_attachment" {
  count = var.create_user_role ? 1 : 0
  
  role       = aws_iam_role.amazon_q_user_role[0].name
  policy_arn = aws_iam_policy.amazon_q_user_policy[0].arn
}

# IAM Identity Center (SSO) integration for Amazon Q Developer Pro
# This resource is created only if Identity Center integration is enabled
resource "aws_ssoadmin_permission_set" "amazon_q_permission_set" {
  count = var.enable_identity_center ? 1 : 0
  
  name             = "${var.resource_prefix}-amazon-q-developer"
  description      = "Permission set for Amazon Q Developer Pro access"
  instance_arn     = var.identity_center_instance_arn
  session_duration = var.session_duration

  tags = {
    Name        = "${var.resource_prefix}-amazon-q-developer"
    Description = "Permission set for Amazon Q Developer Pro"
  }
}

# Inline policy for the Identity Center permission set
resource "aws_ssoadmin_permission_set_inline_policy" "amazon_q_inline_policy" {
  count = var.enable_identity_center ? 1 : 0
  
  inline_policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "q:*",
          "codewhisperer:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:ListRoles",
          "iam:GetRole"
        ]
        Resource = "*"
      }
    ]
  })
  instance_arn       = var.identity_center_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.amazon_q_permission_set[0].arn
}

# Account assignment for Identity Center permission set
resource "aws_ssoadmin_account_assignment" "amazon_q_assignment" {
  count = var.enable_identity_center && length(var.identity_center_user_ids) > 0 ? length(var.identity_center_user_ids) : 0
  
  instance_arn       = var.identity_center_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.amazon_q_permission_set[0].arn
  principal_id       = var.identity_center_user_ids[count.index]
  principal_type     = "USER"
  target_id          = data.aws_caller_identity.current.account_id
  target_type        = "AWS_ACCOUNT"
}

# CloudWatch Log Group for Amazon Q Developer usage monitoring
resource "aws_cloudwatch_log_group" "amazon_q_usage_logs" {
  count = var.enable_usage_monitoring ? 1 : 0
  
  name              = "/aws/amazonq/${var.resource_prefix}-usage"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.resource_prefix}-amazon-q-usage-logs"
    Description = "Log group for Amazon Q Developer usage monitoring"
  }
}

# CloudWatch dashboard for Amazon Q Developer metrics
resource "aws_cloudwatch_dashboard" "amazon_q_dashboard" {
  count = var.enable_usage_monitoring ? 1 : 0
  
  dashboard_name = "${var.resource_prefix}-amazon-q-metrics"

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
            ["AWS/Q", "RequestCount"],
            [".", "ResponseTime"],
            [".", "ErrorCount"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Amazon Q Developer Usage Metrics"
          period  = 300
        }
      }
    ]
  })
}

# S3 bucket for storing Amazon Q Developer configuration and logs (optional)
resource "aws_s3_bucket" "amazon_q_config_bucket" {
  count = var.create_config_bucket ? 1 : 0
  
  bucket        = "${var.resource_prefix}-amazon-q-config-${random_string.bucket_suffix[0].result}"
  force_destroy = var.force_destroy_bucket

  tags = {
    Name        = "${var.resource_prefix}-amazon-q-config"
    Description = "Configuration and logs storage for Amazon Q Developer"
  }
}

# Random string for S3 bucket suffix to ensure uniqueness
resource "random_string" "bucket_suffix" {
  count = var.create_config_bucket ? 1 : 0
  
  length  = 8
  special = false
  upper   = false
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "amazon_q_config_versioning" {
  count = var.create_config_bucket ? 1 : 0
  
  bucket = aws_s3_bucket.amazon_q_config_bucket[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "amazon_q_config_encryption" {
  count = var.create_config_bucket ? 1 : 0
  
  bucket = aws_s3_bucket.amazon_q_config_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "amazon_q_config_pab" {
  count = var.create_config_bucket ? 1 : 0
  
  bucket = aws_s3_bucket.amazon_q_config_bucket[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Local file to store setup instructions
resource "local_file" "setup_instructions" {
  filename = "${path.module}/amazon-q-setup-guide.md"
  content  = templatefile("${path.module}/templates/setup-guide.md.tpl", {
    resource_prefix = var.resource_prefix
    aws_region      = var.aws_region
    account_id      = data.aws_caller_identity.current.account_id
    admin_role_arn  = var.create_admin_role ? aws_iam_role.amazon_q_admin_role[0].arn : "Not created"
    user_role_arn   = var.create_user_role ? aws_iam_role.amazon_q_user_role[0].arn : "Not created"
    config_bucket   = var.create_config_bucket ? aws_s3_bucket.amazon_q_config_bucket[0].bucket : "Not created"
  })
}

# Create the setup guide template file
resource "local_file" "setup_guide_template" {
  filename = "${path.module}/templates/setup-guide.md.tpl"
  content  = <<-EOT
# Amazon Q Developer Setup Guide

This guide provides instructions for setting up Amazon Q Developer with the infrastructure created by Terraform.

## Infrastructure Summary

- **AWS Region**: ${aws_region}
- **AWS Account ID**: ${account_id}
- **Resource Prefix**: ${resource_prefix}

## Created Resources

### IAM Roles and Policies
- **Admin Role ARN**: ${admin_role_arn}
- **User Role ARN**: ${user_role_arn}

### Storage
- **Configuration Bucket**: ${config_bucket}

## Amazon Q Developer Setup Instructions

### 1. Install VS Code Extension

```bash
# Install the Amazon Q Developer extension
code --install-extension AmazonWebServices.amazon-q-vscode
```

### 2. Authentication Options

#### Option A: AWS Builder ID (Free)
1. Open VS Code and click the Amazon Q icon in the activity bar
2. Select "Use for free with AWS Builder ID"
3. Complete the authentication flow in your browser
4. Return to VS Code to complete setup

#### Option B: IAM Identity Center (Pro)
1. Open VS Code and click the Amazon Q icon in the activity bar
2. Select "Connect with IAM Identity Center"
3. Enter your organization's start URL
4. Complete the authentication flow
5. Return to VS Code to complete setup

### 3. Verify Installation

1. Open a new file in VS Code (e.g., `test.py`)
2. Start typing code to see inline suggestions
3. Open the Amazon Q chat panel
4. Ask a question like "How do I create an S3 bucket?"

### 4. Configure Settings

Access Amazon Q settings in VS Code:
1. Open Settings (Ctrl+, or Cmd+,)
2. Search for "Amazon Q"
3. Adjust preferences as needed

## Additional Resources

- [Amazon Q Developer Documentation](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/)
- [AWS Builder ID Setup](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/auth-builder-id.html)
- [IAM Identity Center Setup](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/auth-iam-ic.html)

Generated on: $(date)
EOT
}