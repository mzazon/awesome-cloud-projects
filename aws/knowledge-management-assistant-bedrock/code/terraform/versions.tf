# =============================================================================
# Provider and Version Requirements for Knowledge Management Assistant
# =============================================================================
# This file specifies the required Terraform version and provider versions
# to ensure compatibility and reproducible deployments.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # AWS Provider for core AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating unique suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive provider for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }

  # Optional: Configure Terraform Cloud or S3 backend for state management
  # Uncomment and configure as needed for your environment
  #
  # backend "s3" {
  #   bucket  = "your-terraform-state-bucket"
  #   key     = "knowledge-management-assistant/terraform.tfstate"
  #   region  = "us-east-1"
  #   encrypt = true
  #   
  #   # Optional: DynamoDB table for state locking
  #   dynamodb_table = "terraform-state-locks"
  # }
  #
  # backend "remote" {
  #   organization = "your-terraform-cloud-org"
  #   
  #   workspaces {
  #     name = "knowledge-management-assistant"
  #   }
  # }
}

# =============================================================================
# AWS Provider Configuration
# =============================================================================

provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project            = var.project_name
      Environment        = var.environment
      ManagedBy          = "terraform"
      Recipe             = "bedrock-knowledge-assistant"
      TerraformWorkspace = terraform.workspace
      CreatedDate        = timestamp()
    }
  }

  # Retry configuration for better reliability
  retry_mode      = "adaptive"
  max_retries     = 3

  # Optional: Configure assume role for cross-account deployments
  # Uncomment and configure if deploying across AWS accounts
  #
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT-ID:role/TerraformExecutionRole"
  #   session_name = "TerraformSession"
  # }

  # Optional: Configure specific AWS profile
  # Uncomment if using named AWS profiles
  #
  # profile = "your-aws-profile"
}

# =============================================================================
# Provider Aliases for Multi-Region Deployments (Optional)
# =============================================================================

# Uncomment if you need to deploy resources in multiple regions
# For example, for disaster recovery or global distribution

# provider "aws" {
#   alias  = "us_west_2"
#   region = "us-west-2"
#   
#   default_tags {
#     tags = {
#       Project     = var.project_name
#       Environment = var.environment
#       ManagedBy   = "terraform"
#       Recipe      = "bedrock-knowledge-assistant"
#       Region      = "us-west-2"
#     }
#   }
# }

# provider "aws" {
#   alias  = "eu_west_1"
#   region = "eu-west-1"
#   
#   default_tags {
#     tags = {
#       Project     = var.project_name
#       Environment = var.environment
#       ManagedBy   = "terraform"
#       Recipe      = "bedrock-knowledge-assistant"
#       Region      = "eu-west-1"
#     }
#   }
# }

# =============================================================================
# Random Provider Configuration
# =============================================================================

provider "random" {
  # No specific configuration needed for random provider
}

# =============================================================================
# Archive Provider Configuration
# =============================================================================

provider "archive" {
  # No specific configuration needed for archive provider
}

# =============================================================================
# Terraform Configuration Notes
# =============================================================================

# Version Constraints Explanation:
# 
# Terraform >= 1.5.0:
# - Required for the latest Terraform features and bug fixes
# - Ensures compatibility with the provider versions specified
#
# AWS Provider ~> 5.0:
# - Uses the latest AWS provider v5.x series
# - Includes support for the latest AWS services and features
# - Provides better resource management and lifecycle handling
#
# Random Provider ~> 3.1:
# - Stable version with good entropy generation
# - Used for creating unique resource suffixes
#
# Archive Provider ~> 2.2:
# - Used for creating Lambda deployment packages
# - Provides reliable zip file creation

# Upgrade Notes:
# 
# When upgrading provider versions:
# 1. Review the provider changelogs for breaking changes
# 2. Test in a development environment first
# 3. Update version constraints gradually
# 4. Run 'terraform init -upgrade' to update provider versions
# 5. Review and test all resource configurations

# State Management Best Practices:
#
# 1. Use remote state storage (S3 with DynamoDB locking)
# 2. Enable state versioning and backup
# 3. Encrypt state files at rest
# 4. Implement proper IAM permissions for state access
# 5. Use workspace separation for different environments

# Security Considerations:
#
# 1. Store sensitive variables in secure variable stores
# 2. Use IAM roles with minimal required permissions
# 3. Enable AWS CloudTrail for audit logging
# 4. Rotate access keys regularly
# 5. Use AWS Secrets Manager for application secrets