# ============================================================================
# TERRAFORM VERSION AND PROVIDER REQUIREMENTS
# ============================================================================
# This file defines the minimum Terraform version and required providers
# for the enterprise authentication solution with AWS Amplify and external
# identity providers.
#
# Provider versions are pinned to ensure consistent deployments while
# allowing for patch updates within the same minor version.
# ============================================================================

terraform {
  # Minimum Terraform version required for this configuration
  # This version supports all the features used in this module
  required_version = ">= 1.5.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31"
    }

    # Random provider for generating unique suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Optional: Configure backend for state management
  # Uncomment and modify the following block to use remote state storage
  # 
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "enterprise-auth/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  # }
}

# ============================================================================
# AWS PROVIDER CONFIGURATION
# ============================================================================

provider "aws" {
  # AWS region can be set via:
  # 1. Variable: var.aws_region
  # 2. Environment variable: AWS_DEFAULT_REGION
  # 3. AWS config file: ~/.aws/config
  # 4. EC2 instance metadata (when running on EC2)
  region = var.aws_region

  # Default tags applied to all resources created by this provider
  # These tags help with cost allocation, compliance, and resource management
  default_tags {
    tags = {
      # Project identification
      Project     = var.project_name
      Environment = var.environment
      
      # Infrastructure management
      ManagedBy   = "terraform"
      Repository  = "enterprise-authentication-amplify-external-identity-providers"
      
      # Cost allocation tags (if enabled)
      CostCenter   = var.enable_cost_allocation_tags ? var.cost_center : null
      BusinessUnit = var.enable_cost_allocation_tags ? var.business_unit : null
      
      # Compliance and governance
      DataClassification = var.data_classification
      ComplianceFramework = var.compliance_framework != [] ? join(",", var.compliance_framework) : null
      
      # Operational tags
      CreatedBy    = "terraform"
      LastModified = timestamp()
      
      # Recipe identification for tracking
      Recipe = "enterprise-authentication-amplify-external-identity-providers"
    }
  }

  # Optional: Assume role for cross-account deployments
  # Uncomment and modify if deploying to a different AWS account
  # 
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT-ID:role/TerraformExecutionRole"
  #   session_name = "terraform-enterprise-auth"
  #   external_id  = "optional-external-id"
  # }

  # Optional: Ignore specific tags during resource updates
  # This prevents Terraform from detecting changes for tags managed externally
  ignore_tags {
    keys = [
      "LastScanned",      # Security scanning tools
      "BackupSchedule",   # Backup automation
      "MaintenanceWindow" # Maintenance automation
    ]
  }
}

# ============================================================================
# RANDOM PROVIDER CONFIGURATION
# ============================================================================

provider "random" {
  # No specific configuration required for random provider
  # Used for generating unique resource identifiers
}

# ============================================================================
# PROVIDER FEATURE REQUIREMENTS
# ============================================================================

# This configuration requires the following AWS provider features:
# - Cognito User Pools and Identity Pools (GA)
# - Cognito Identity Providers for SAML and OIDC (GA)
# - S3 bucket configurations with versioning and lifecycle (GA)
# - API Gateway REST API with Cognito authorization (GA)
# - AWS Amplify applications and branches (GA)
# - IAM roles and policies with web identity federation (GA)
# - CloudWatch log groups and dashboards (GA)

# ============================================================================
# VERSION COMPATIBILITY NOTES
# ============================================================================

# Terraform >= 1.5.0 is required for:
# - Enhanced validation functions
# - Improved error messages
# - Better performance with large configurations
# - Support for optional object type attributes

# AWS Provider ~> 5.31 provides:
# - Latest Cognito features and security enhancements
# - Enhanced API Gateway integration options
# - Improved S3 bucket security configurations
# - Latest IAM policy syntax support
# - Updated CloudWatch dashboard capabilities

# Random Provider ~> 3.6 provides:
# - Stable random generation algorithms
# - Consistent behavior across Terraform versions
# - Support for various random value types

# ============================================================================
# UPGRADE CONSIDERATIONS
# ============================================================================

# When upgrading provider versions:
# 1. Review provider changelog for breaking changes
# 2. Test in development environment first
# 3. Plan deployment to identify potential issues
# 4. Consider backup strategies for stateful resources
# 5. Update documentation and team processes

# Major version upgrades may require:
# - Configuration syntax updates
# - Resource attribute changes
# - State migration procedures
# - Validation rule adjustments

# ============================================================================
# EXPERIMENTAL FEATURES
# ============================================================================

# This configuration does not use any experimental Terraform features
# All resources and functions are stable and production-ready

# If experimental features are needed in the future:
# - Enable explicitly in terraform block
# - Document usage and migration plans
# - Monitor for graduation to stable features
# - Plan for potential breaking changes