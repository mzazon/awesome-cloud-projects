# =============================================================================
# Terraform and Provider Version Constraints
# =============================================================================
# This file defines the minimum required versions for Terraform and providers
# to ensure compatibility and access to required features for the data lake
# governance infrastructure.

terraform {
  # Require Terraform version 1.5 or higher for latest features and stability
  required_version = ">= 1.5.0"

  required_providers {
    # AWS Provider - Latest version with Lake Formation and DataZone support
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }

    # Random Provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.0"
    }

    # Template Provider for dynamic file generation
    template = {
      source  = "hashicorp/template"
      version = ">= 2.2.0"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and configure based on your organization's requirements
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "data-lake-governance/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# =============================================================================
# AWS Provider Configuration
# =============================================================================

provider "aws" {
  # Use the region specified in variables or default to current AWS CLI region
  region = var.aws_region

  # Default tags applied to all resources created by this provider
  default_tags {
    tags = merge({
      # Core infrastructure tags
      Project           = "Advanced Data Lake Governance"
      ManagedBy         = "Terraform"
      Environment       = var.environment
      DeploymentDate    = timestamp()
      
      # Governance and compliance tags
      DataClassification = "Enterprise"
      Compliance        = var.compliance_mode
      CostCenter        = "DataGovernance"
      
      # Operational tags
      BackupRequired    = "true"
      MonitoringEnabled = "true"
      
      # Security tags
      SecurityReview    = "Required"
      DataGovernance    = "LakeFormation"
    }, var.additional_tags)
  }

  # Ignore tags on resources that are managed by AWS services
  ignore_tags {
    key_prefixes = ["aws:", "datazone:", "lakeformation:"]
  }
}

# =============================================================================
# Random Provider Configuration
# =============================================================================

provider "random" {
  # No additional configuration required for random provider
}

# =============================================================================
# Template Provider Configuration
# =============================================================================

provider "template" {
  # No additional configuration required for template provider
}

# =============================================================================
# Provider Feature Requirements
# =============================================================================

# This configuration requires the following AWS provider features:
# - Lake Formation support (available in AWS provider >= 4.0.0)
# - DataZone support (available in AWS provider >= 5.0.0)
# - S3 bucket encryption configuration (available in AWS provider >= 4.0.0)
# - Glue job configuration with Spark UI support (available in AWS provider >= 3.0.0)
# - CloudWatch metric alarms with tags (available in AWS provider >= 3.0.0)
# - SNS topic with tags (available in AWS provider >= 3.0.0)
#
# The minimum version requirement of >= 5.0.0 ensures all required features
# are available and provides the latest security updates and bug fixes.

# =============================================================================
# Experimental Features (if needed)
# =============================================================================

# Note: Some advanced DataZone features may be in preview or experimental.
# Enable experimental features only if required and supported in your environment.
# 
# terraform {
#   experiments = [module_variable_optional_attrs]
# }