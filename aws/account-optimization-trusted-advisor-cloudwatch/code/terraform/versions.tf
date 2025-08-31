# ==============================================================================
# Terraform Provider Versions and Requirements
# ==============================================================================
# This file defines the Terraform version constraints and required providers
# for the AWS Trusted Advisor CloudWatch monitoring infrastructure.
# Using specific version constraints ensures consistent deployments and
# prevents breaking changes from affecting existing infrastructure.
# ==============================================================================

terraform {
  # Minimum Terraform version required for this configuration
  # Version 1.0+ provides stable features and better error messages
  required_version = ">= 1.0"
  
  # Required providers with version constraints
  required_providers {
    # AWS Provider - Used for all AWS resource management
    # Version 5.0+ provides the latest features and security improvements
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 6.0"
    }
    
    # Random Provider - Used for generating unique resource identifiers
    # Version 3.1+ provides stable random generation functions
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1, < 4.0"
    }
  }
  
  # Optional: Terraform Cloud/Enterprise configuration
  # Uncomment and configure if using Terraform Cloud for state management
  # cloud {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "trusted-advisor-monitoring"
  #   }
  # }
  
  # Optional: S3 backend configuration for state management
  # Uncomment and configure for production deployments
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "trusted-advisor-monitoring/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  # }
}

# ==============================================================================
# AWS Provider Configuration
# ==============================================================================
# Configure the AWS Provider with appropriate settings for Trusted Advisor
# monitoring. This provider will be used to create all AWS resources.

provider "aws" {
  # Region must be us-east-1 for Trusted Advisor metrics availability
  # All Trusted Advisor metrics are published exclusively to this region
  region = "us-east-1"
  
  # Default tags applied to all resources created by this provider
  # These tags help with resource identification, cost allocation, and compliance
  default_tags {
    tags = {
      TerraformManaged = "true"
      Module          = "trusted-advisor-monitoring"
      Repository      = "aws-recipes"
      LastUpdated     = formatdate("YYYY-MM-DD", timestamp())
    }
  }
  
  # Assume role configuration (optional)
  # Uncomment if deploying across AWS accounts or using role assumption
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT-ID:role/TerraformDeploymentRole"
  #   session_name = "TrustedAdvisorMonitoring"
  # }
}

# ==============================================================================
# Random Provider Configuration
# ==============================================================================
# Configure the Random Provider for generating unique identifiers
# This ensures resource names are unique across multiple deployments

provider "random" {
  # No specific configuration required for the random provider
  # It will be used to generate unique suffixes for resource naming
}

# ==============================================================================
# Provider Feature Compatibility Notes
# ==============================================================================
# This configuration is compatible with the following AWS provider features:
#
# AWS Provider >= 5.0:
# - Enhanced CloudWatch alarm configurations
# - Improved SNS topic management
# - Better error handling and validation
# - Support for latest AWS service features
#
# Random Provider >= 3.1:
# - Stable random_id resource behavior
# - Consistent random generation across plan/apply cycles
# - Better entropy for unique identifier generation
#
# Terraform >= 1.0:
# - Stable configuration language features
# - Enhanced validation capabilities
# - Better provider dependency management
# - Improved error messages and debugging
# ==============================================================================

# ==============================================================================
# Version Upgrade Guidelines
# ==============================================================================
# When upgrading provider versions:
#
# 1. AWS Provider Upgrades:
#    - Review the provider changelog for breaking changes
#    - Test in a non-production environment first
#    - Pay attention to resource attribute changes
#    - Update any deprecated resource configurations
#
# 2. Terraform Version Upgrades:
#    - Use `terraform init -upgrade` to update providers
#    - Run `terraform plan` to check for configuration changes
#    - Update .terraform.lock.hcl in version control
#    - Test thoroughly before applying in production
#
# 3. Backward Compatibility:
#    - This configuration maintains compatibility with AWS provider 4.x
#    - Consider updating to take advantage of new features
#    - Some advanced features may require newer provider versions
# ==============================================================================