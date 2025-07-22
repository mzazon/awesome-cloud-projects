# =============================================================================
# Terraform and Provider Version Requirements
# =============================================================================

terraform {
  # Specify minimum Terraform version
  required_version = ">= 1.5.0"

  # Required providers and their version constraints
  required_providers {
    # AWS Provider for all AWS resources
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

  # Optional: Configure backend for state management
  # Uncomment and configure as needed for your environment
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "workspaces/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "your-terraform-lock-table"
  # }
}

# =============================================================================
# Provider Configuration
# =============================================================================

# Configure the AWS Provider
provider "aws" {
  # AWS region will be determined by:
  # 1. AWS_REGION environment variable
  # 2. AWS CLI profile configuration
  # 3. EC2 instance metadata (if running on EC2)

  # Optional: Specify default tags for all resources
  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Project     = "workforce-productivity-workspaces"
      Environment = var.environment
    }
  }

  # Optional: Assume role configuration for cross-account access
  # Uncomment and configure as needed
  #
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT_ID:role/TerraformRole"
  #   session_name = "terraform-workspaces-deployment"
  # }
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required for random provider
}

# =============================================================================
# Data Sources for Provider Information
# =============================================================================

# Verify AWS provider and region information
data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# =============================================================================
# Provider Feature Compatibility
# =============================================================================

# This configuration is compatible with:
# - AWS Provider 5.x series
# - Terraform 1.5.0 and later
# - All AWS regions where WorkSpaces is available
#
# Tested with:
# - AWS Provider 5.31.0
# - Terraform 1.6.0
#
# For the latest compatibility information, see:
# - https://registry.terraform.io/providers/hashicorp/aws/latest
# - https://developer.hashicorp.com/terraform/language/providers/requirements