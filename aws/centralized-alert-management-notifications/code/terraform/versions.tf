# =============================================================================
# PROVIDER VERSIONS AND REQUIREMENTS
# =============================================================================
# This file specifies the Terraform version requirements and provider 
# configurations for the centralized alert management infrastructure.
# These version constraints ensure compatibility and stable deployments.
# =============================================================================

terraform {
  # Terraform version requirement
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider - Primary cloud provider for all resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Random Provider - For generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Terraform Cloud/Enterprise configuration (optional)
  # Uncomment and configure if using Terraform Cloud or Enterprise
  # cloud {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "centralized-alert-management"
  #   }
  # }

  # Backend configuration for state management
  # Uncomment and configure for remote state storage
  # backend "s3" {
  #   bucket  = "your-terraform-state-bucket"
  #   key     = "centralized-alert-management/terraform.tfstate"
  #   region  = "us-east-1"
  #   encrypt = true
  #   
  #   # DynamoDB table for state locking
  #   dynamodb_table = "terraform-state-locks"
  # }
}

# =============================================================================
# AWS PROVIDER CONFIGURATION
# =============================================================================

provider "aws" {
  # AWS region will be determined by:
  # 1. Environment variable AWS_DEFAULT_REGION
  # 2. AWS CLI configuration profile
  # 3. EC2 instance metadata (if running on EC2)
  
  # Default tags applied to all AWS resources
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = "Centralized Alert Management"
      Repository  = "aws-recipes/centralized-alert-management-notifications"
      CreatedBy   = "Infrastructure as Code"
    }
  }

  # Assume role configuration (optional)
  # Uncomment if deploying via assume role
  # assume_role {
  #   role_arn = "arn:aws:iam::ACCOUNT-ID:role/TerraformExecutionRole"
  # }
}

# =============================================================================
# RANDOM PROVIDER CONFIGURATION
# =============================================================================

provider "random" {
  # No specific configuration needed for random provider
  # Used for generating unique suffixes for resource names
}

# =============================================================================
# PROVIDER FEATURE REQUIREMENTS
# =============================================================================

# This configuration requires the following AWS services and features:
# 
# AWS Services Used:
# - AWS User Notifications (notifications.amazonaws.com)
# - AWS User Notifications Contacts (notificationscontacts.amazonaws.com) 
# - Amazon S3 (s3.amazonaws.com)
# - Amazon CloudWatch (monitoring.amazonaws.com)
# - AWS EventBridge (events.amazonaws.com)
#
# Required AWS API Permissions:
# - notifications:* (User Notifications management)
# - notificationscontacts:* (Contact management)
# - s3:* (S3 bucket and object operations)
# - cloudwatch:* (CloudWatch alarms and metrics)
# - events:* (EventBridge rules and targets)
# - iam:PassRole (For service-linked roles)
# - sts:GetCallerIdentity (For account information)
#
# Regional Availability:
# - AWS User Notifications is available in most AWS regions
# - Check service availability in your target region before deployment
# - Some features may have regional limitations
#
# Cost Considerations:
# - CloudWatch alarms: $0.10 per alarm per month
# - S3 storage: Standard rates apply based on usage
# - S3 request metrics: Additional charges if enabled
# - User Notifications: No additional service charges
# - Data transfer: Standard AWS data transfer rates
#
# Security Requirements:
# - IAM permissions for Terraform execution
# - Email address verification for notification contacts
# - Appropriate resource tagging for governance
# - Encryption enabled for data at rest and in transit

# =============================================================================
# VERSION COMPATIBILITY MATRIX
# =============================================================================

# Terraform Version: >= 1.0
# - Supports modern HCL syntax and features
# - Required for advanced validation and functions
# - Compatible with Terraform Cloud/Enterprise
#
# AWS Provider Version: ~> 5.0
# - Includes User Notifications service support
# - Latest S3 bucket resource configurations
# - Enhanced CloudWatch alarm capabilities
# - Improved EventBridge integration
#
# Random Provider Version: ~> 3.1
# - Stable random string generation
# - Consistent behavior across deployments
# - No breaking changes expected
#
# Minimum Required Versions:
# - Terraform: 1.0.0
# - AWS Provider: 5.0.0
# - Random Provider: 3.1.0

# =============================================================================
# EXPERIMENTAL FEATURES AND DEPRECATIONS
# =============================================================================

# Experimental Features:
# - None currently in use
# - Future versions may adopt provider-defined functions
#
# Deprecated Features Avoided:
# - Legacy S3 bucket configurations (replaced with separate resources)
# - Deprecated CloudWatch alarm configurations
# - Old EventBridge syntax (using current event patterns)
#
# Provider Warnings:
# - AWS provider may show warnings about future resource changes
# - Monitor provider release notes for upcoming deprecations
# - Plan regular updates to maintain compatibility

# =============================================================================
# DEVELOPMENT AND TESTING VERSIONS
# =============================================================================

# For development environments, you may use:
# terraform {
#   required_version = ">= 1.0"
#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = ">= 5.0, < 6.0"  # More restrictive for stability
#     }
#     random = {
#       source  = "hashicorp/random" 
#       version = "= 3.6.0"  # Pin to specific version for testing
#     }
#   }
# }

# =============================================================================
# UPGRADE CONSIDERATIONS
# =============================================================================

# When upgrading providers:
# 1. Review provider release notes for breaking changes
# 2. Test in non-production environment first
# 3. Update terraform {} block version constraints
# 4. Run 'terraform init -upgrade' to update providers
# 5. Run 'terraform plan' to review changes
# 6. Apply changes incrementally if needed
#
# Provider Upgrade Commands:
# terraform init -upgrade
# terraform providers lock -platform=linux_amd64 -platform=darwin_amd64 -platform=windows_amd64
#
# State Migration (if needed):
# terraform state pull > state_backup.json
# terraform apply  # Apply any state migrations
# terraform state push state_backup.json  # Only if rollback needed