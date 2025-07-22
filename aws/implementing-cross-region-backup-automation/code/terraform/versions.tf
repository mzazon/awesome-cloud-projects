# ==============================================================================
# Multi-Region Backup Strategies - Provider and Version Configuration
# ==============================================================================
# This file defines the required Terraform version and provider configurations
# for the multi-region backup strategy implementation. It includes all necessary
# provider aliases for multi-region deployment and version constraints for
# stability and compatibility.
# ==============================================================================

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Archive provider for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# ==============================================================================
# AWS Provider Configuration - Primary Region
# ==============================================================================

# Default AWS provider for primary region
provider "aws" {
  region = var.primary_region
  
  # Default tags applied to all resources in the primary region
  default_tags {
    tags = {
      Project             = var.project_name
      Environment         = var.environment
      ManagedBy           = "Terraform"
      BackupStrategy      = "MultiRegion"
      PrimaryRegion       = var.primary_region
      TerraformWorkspace  = terraform.workspace
      CreatedBy           = "terraform"
    }
  }
}

# ==============================================================================
# AWS Provider Configuration - Secondary Region
# ==============================================================================

# AWS provider alias for secondary region (cross-region backup copies)
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  
  # Default tags applied to all resources in the secondary region
  default_tags {
    tags = {
      Project             = var.project_name
      Environment         = var.environment
      ManagedBy           = "Terraform"
      BackupStrategy      = "MultiRegion"
      PrimaryRegion       = var.primary_region
      SecondaryRegion     = var.secondary_region
      RegionType          = "Secondary"
      TerraformWorkspace  = terraform.workspace
      CreatedBy           = "terraform"
    }
  }
}

# ==============================================================================
# AWS Provider Configuration - Tertiary Region
# ==============================================================================

# AWS provider alias for tertiary region (long-term archival)
provider "aws" {
  alias  = "tertiary"
  region = var.tertiary_region
  
  # Default tags applied to all resources in the tertiary region
  default_tags {
    tags = {
      Project             = var.project_name
      Environment         = var.environment
      ManagedBy           = "Terraform"
      BackupStrategy      = "MultiRegion"
      PrimaryRegion       = var.primary_region
      TertiaryRegion      = var.tertiary_region
      RegionType          = "Tertiary"
      Purpose             = "LongTermArchival"
      TerraformWorkspace  = terraform.workspace
      CreatedBy           = "terraform"
    }
  }
}

# ==============================================================================
# Archive Provider Configuration
# ==============================================================================

# Archive provider for creating Lambda function deployment packages
provider "archive" {
  # No specific configuration required for archive provider
}

# ==============================================================================
# Random Provider Configuration
# ==============================================================================

# Random provider for generating unique identifiers
provider "random" {
  # No specific configuration required for random provider
}

# ==============================================================================
# Backend Configuration Template
# ==============================================================================

# Uncomment and modify the backend configuration below if you want to use
# remote state storage. This is recommended for production deployments.

/*
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "backup-strategies/multi-region/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
    
    # Uncomment and configure if using role assumption
    # role_arn = "arn:aws:iam::ACCOUNT-ID:role/TerraformRole"
  }
}
*/

# Alternative backend configuration for Terraform Cloud
/*
terraform {
  cloud {
    organization = "your-organization"
    
    workspaces {
      name = "multi-region-backup-strategies"
    }
  }
}
*/

# ==============================================================================
# Provider Version Constraints and Compatibility Notes
# ==============================================================================

# AWS Provider Version Constraints:
# - Version 5.x is required for the latest AWS Backup features
# - Minimum version 5.0 ensures compatibility with multi-region KMS keys
# - Latest 5.x versions include enhanced backup vault features
# - Cross-region backup copy functionality requires 5.0+

# Archive Provider Version Constraints:
# - Version 2.4+ includes improved zip file handling
# - Required for Lambda function deployment packages
# - Stable API ensures consistent archive creation

# Random Provider Version Constraints:
# - Version 3.6+ provides enhanced random string generation
# - Used for creating unique resource suffixes
# - Ensures deterministic behavior across Terraform runs

# Terraform Version Constraints:
# - Minimum version 1.0 required for stable provider handling
# - Provider aliases require Terraform 1.0+
# - Multi-provider configurations work best with 1.0+

# ==============================================================================
# Provider Feature Requirements
# ==============================================================================

# Required AWS API permissions for this configuration:
# - backup:* (for AWS Backup operations)
# - iam:* (for creating service roles and policies)
# - kms:* (for encryption key management)
# - sns:* (for notification setup)
# - lambda:* (for backup validation functions)
# - events:* (for EventBridge rules and targets)
# - logs:* (for CloudWatch logging)
# - ec2:DescribeRegions (for region validation)

# Cross-region considerations:
# - KMS keys must support multi-region or be created in each region
# - IAM roles are global but policies may need region-specific ARNs
# - EventBridge rules are region-specific
# - SNS topics are region-specific

# ==============================================================================
# Compatibility Notes
# ==============================================================================

# This configuration is compatible with:
# - AWS CLI v2.0+
# - Terraform 1.0+
# - All AWS regions that support AWS Backup
# - AWS GovCloud (with minor modifications)
# - AWS China regions (with provider adjustments)

# Known limitations:
# - Some AWS services may not be available in all regions
# - Cross-region data transfer charges apply
# - Backup vault lock features may have regional availability
# - Lambda runtime versions vary by region

# Migration considerations:
# - When upgrading providers, check for breaking changes
# - Test in non-production environments first
# - Review AWS Backup service updates for new features
# - Monitor deprecated features and plan migrations