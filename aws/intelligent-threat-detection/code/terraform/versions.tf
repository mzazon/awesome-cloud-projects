# ==============================================================================
# Terraform and Provider Version Requirements
# ==============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating unique identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Uncomment and configure backend for production deployments
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "guardduty-threat-detection/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  # }
}

# ==============================================================================
# Provider Configuration
# ==============================================================================

# Configure the AWS Provider
provider "aws" {
  # AWS credentials and region should be configured via:
  # - AWS credentials file (~/.aws/credentials)
  # - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION)
  # - IAM roles (recommended for EC2/Lambda/ECS)
  # - AWS CLI configuration (aws configure)

  default_tags {
    tags = {
      ManagedBy       = "Terraform"
      Project         = "GuardDuty Threat Detection"
      Repository      = "cloud-recipes"
      Recipe          = "guardduty-threat-detection"
      DeploymentDate  = timestamp()
    }
  }
}

# Configure the Random Provider (no additional configuration required)
provider "random" {}

# ==============================================================================
# Backend Configuration Examples
# ==============================================================================

# Example S3 backend configuration for production:
# Store Terraform state in S3 with DynamoDB locking for team collaboration
#
# terraform {
#   backend "s3" {
#     bucket                  = "your-company-terraform-state"
#     key                     = "security/guardduty-threat-detection/terraform.tfstate"
#     region                  = "us-east-1"
#     encrypt                 = true
#     dynamodb_table         = "terraform-state-locks"
#     workspace_key_prefix   = "workspaces"
#     
#     # Optional: Server-side encryption with KMS
#     kms_key_id             = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
#     
#     # Optional: Versioning (recommended)
#     versioning             = true
#   }
# }

# Example remote backend with state locking:
# This ensures only one person can modify infrastructure at a time
#
# terraform {
#   backend "remote" {
#     organization = "your-organization"
#     
#     workspaces {
#       name = "guardduty-threat-detection"
#     }
#   }
# }

# ==============================================================================
# Version Constraints Explanation
# ==============================================================================

# Terraform Version Constraint: ">= 1.0"
# - Requires Terraform 1.0 or later for stability and feature support
# - Ensures compatibility with modern Terraform language features
# - Provides access to improved state management and error handling

# AWS Provider Version Constraint: "~> 5.0"
# - Uses AWS Provider v5.x.x (but not v6.x.x)
# - Provides access to latest AWS services and features
# - Ensures compatibility with current GuardDuty functionality
# - Includes support for:
#   * GuardDuty malware protection
#   * Kubernetes audit logs monitoring
#   * S3 protection features
#   * Enhanced finding publishing options

# Random Provider Version Constraint: "~> 3.1"
# - Uses Random Provider v3.1.x or later within v3.x.x
# - Provides stable random resource generation
# - Ensures consistent behavior across Terraform versions

# ==============================================================================
# Required IAM Permissions
# ==============================================================================

# The following IAM permissions are required for this Terraform configuration:
#
# GuardDuty Permissions:
# - guardduty:CreateDetector
# - guardduty:GetDetector
# - guardduty:UpdateDetector
# - guardduty:DeleteDetector
# - guardduty:CreatePublishingDestination
# - guardduty:DeletePublishingDestination
# - guardduty:CreateThreatIntelSet
# - guardduty:DeleteThreatIntelSet
# - guardduty:CreateIPSet
# - guardduty:DeleteIPSet
# - guardduty:TagResource
# - guardduty:ListTagsForResource
#
# S3 Permissions:
# - s3:CreateBucket
# - s3:DeleteBucket
# - s3:GetBucketLocation
# - s3:GetBucketVersioning
# - s3:PutBucketVersioning
# - s3:GetBucketEncryption
# - s3:PutBucketEncryption
# - s3:GetBucketPublicAccessBlock
# - s3:PutBucketPublicAccessBlock
# - s3:GetBucketLifecycleConfiguration
# - s3:PutBucketLifecycleConfiguration
# - s3:GetBucketPolicy
# - s3:PutBucketPolicy
# - s3:DeleteBucketPolicy
# - s3:GetBucketTagging
# - s3:PutBucketTagging
#
# SNS Permissions:
# - sns:CreateTopic
# - sns:DeleteTopic
# - sns:GetTopicAttributes
# - sns:SetTopicAttributes
# - sns:Subscribe
# - sns:Unsubscribe
# - sns:ListSubscriptionsByTopic
# - sns:TagResource
# - sns:ListTagsForResource
#
# EventBridge Permissions:
# - events:PutRule
# - events:DeleteRule
# - events:PutTargets
# - events:RemoveTargets
# - events:DescribeRule
# - events:ListTargetsByRule
# - events:TagResource
# - events:ListTagsForResource
#
# CloudWatch Permissions:
# - cloudwatch:PutDashboard
# - cloudwatch:DeleteDashboards
# - cloudwatch:GetDashboard
# - cloudwatch:PutMetricAlarm
# - cloudwatch:DeleteAlarms
# - cloudwatch:DescribeAlarms
# - cloudwatch:TagResource
# - cloudwatch:ListTagsForResource
#
# KMS Permissions (if SNS encryption enabled):
# - kms:CreateKey
# - kms:DeleteKey
# - kms:DescribeKey
# - kms:GetKeyPolicy
# - kms:PutKeyPolicy
# - kms:CreateAlias
# - kms:DeleteAlias
# - kms:TagResource
# - kms:ListResourceTags
#
# IAM Permissions:
# - iam:GetRole (for service-linked roles)
# - iam:CreateServiceLinkedRole (if GuardDuty service-linked role doesn't exist)

# ==============================================================================
# Terraform State Considerations
# ==============================================================================

# Local State (Development):
# - Default for this configuration
# - State stored in local terraform.tfstate file
# - Suitable for development and testing
# - NOT recommended for production use

# Remote State (Production):
# - Configure backend for team collaboration
# - Enables state locking to prevent conflicts
# - Provides state versioning and backup
# - Essential for production deployments
# - Consider using S3 + DynamoDB or Terraform Cloud

# State Security:
# - Terraform state may contain sensitive information
# - Ensure backend storage is encrypted
# - Limit access to state files
# - Use state locking to prevent corruption
# - Regular backups of state files