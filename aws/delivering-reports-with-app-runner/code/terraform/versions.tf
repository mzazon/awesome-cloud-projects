# =============================================================================
# Email Reports Infrastructure - Provider and Version Requirements
# =============================================================================
# Terraform and provider version constraints to ensure compatibility
# and reproducible deployments across different environments.

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.5"

  # Required providers with version constraints
  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# =============================================================================
# Provider Configurations
# =============================================================================

# AWS Provider configuration
provider "aws" {
  # AWS region can be set via:
  # 1. AWS_REGION environment variable
  # 2. AWS CLI configuration (~/.aws/config)
  # 3. Terraform variables (uncomment region line below)
  # region = var.aws_region

  # Default tags applied to all resources created by this provider
  default_tags {
    tags = merge(
      var.common_tags,
      {
        Environment = var.environment
        Terraform   = "true"
        Recipe      = "scheduled-email-reports-app-runner-ses"
      }
    )
  }
}

# Random Provider configuration
provider "random" {
  # No specific configuration needed for the random provider
}