# =====================================================
# Terraform and Provider Version Requirements
# =====================================================
# This file specifies the minimum versions required for
# Terraform and all providers used in this configuration.

terraform {
  # Require Terraform version 1.0 or higher for best practices
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # AWS Provider - Official provider for Amazon Web Services
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Use AWS Provider 5.x for latest features and EventBridge Scheduler support
    }

    # Random Provider - For generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"  # Stable version for random ID generation
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and configure as needed for your environment
  
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "business-notifications/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }

  # Alternative: Use Terraform Cloud backend
  # backend "remote" {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "business-notifications"
  #   }
  # }
}

# =====================================================
# Provider Configuration
# =====================================================

# Configure the AWS Provider
provider "aws" {
  # Region will be determined by:
  # 1. AWS_REGION environment variable
  # 2. ~/.aws/config file
  # 3. EC2 instance metadata service (if running on EC2)
  
  # Optional: Specify default tags for all resources
  default_tags {
    tags = {
      Terraform   = "true"
      Environment = var.environment
      Project     = "BusinessNotifications"
      Repository  = "recipes"
      Recipe      = "simple-business-notifications-eventbridge-scheduler-sns"
    }
  }

  # Optional: Configure assume role for cross-account deployments
  # assume_role {
  #   role_arn = "arn:aws:iam::ACCOUNT-ID:role/TerraformExecutionRole"
  # }
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required for random provider
}

# =====================================================
# Terraform Configuration Best Practices
# =====================================================

# Enable experimental features if needed
# terraform {
#   experiments = []
# }

# Configure provider-specific features
# provider "aws" {
#   # Enable specific AWS features
#   ignore_tags {
#     key_prefixes = ["aws:", "kubernetes.io/"]
#   }
#   
#   # Configure retry behavior
#   retry_mode = "adaptive"
#   max_retries = 5
# }

# =====================================================
# Version Compatibility Notes
# =====================================================

# AWS Provider Version 5.x Features Used:
# - EventBridge Scheduler resources (aws_scheduler_*)
# - Enhanced SNS topic configuration
# - Improved IAM policy document data sources
# - CloudWatch log group advanced features
# - SQS queue redrive policy improvements

# Terraform Version 1.x Features Used:
# - Enhanced variable validation
# - Improved provider configuration
# - Better error messages and debugging
# - Module composition improvements
# - State management enhancements

# =====================================================
# Provider Feature Requirements
# =====================================================

# This configuration requires the following AWS services
# to be available in your target region:
# - Amazon EventBridge (including Scheduler)
# - Amazon Simple Notification Service (SNS)  
# - Amazon Simple Queue Service (SQS)
# - AWS Identity and Access Management (IAM)
# - Amazon CloudWatch (Logs)

# Regional Service Availability:
# EventBridge Scheduler is available in most AWS regions.
# Verify availability in your target region before deployment.

# =====================================================
# Minimum Permission Requirements
# =====================================================

# The IAM user or role executing this Terraform configuration
# requires the following minimum permissions:

# SNS Permissions:
# - sns:CreateTopic
# - sns:DeleteTopic
# - sns:GetTopicAttributes
# - sns:SetTopicAttributes
# - sns:Subscribe
# - sns:Unsubscribe
# - sns:ListSubscriptionsByTopic

# EventBridge Scheduler Permissions:
# - scheduler:CreateScheduleGroup
# - scheduler:DeleteScheduleGroup
# - scheduler:GetScheduleGroup
# - scheduler:CreateSchedule
# - scheduler:DeleteSchedule
# - scheduler:GetSchedule
# - scheduler:UpdateSchedule

# IAM Permissions:
# - iam:CreateRole
# - iam:DeleteRole
# - iam:GetRole
# - iam:CreatePolicy
# - iam:DeletePolicy
# - iam:AttachRolePolicy
# - iam:DetachRolePolicy
# - iam:PassRole

# SQS Permissions (if SQS integration enabled):
# - sqs:CreateQueue
# - sqs:DeleteQueue
# - sqs:GetQueueAttributes
# - sqs:SetQueueAttributes

# CloudWatch Permissions (if logging enabled):
# - logs:CreateLogGroup
# - logs:CreateLogStream
# - logs:DeleteLogGroup
# - logs:DescribeLogGroups

# General Permissions:
# - sts:GetCallerIdentity
# - tag:GetResources
# - tag:TagResources
# - tag:UntagResources