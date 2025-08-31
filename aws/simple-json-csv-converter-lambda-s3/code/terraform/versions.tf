# =============================================================================
# TERRAFORM AND PROVIDER VERSIONS
# =============================================================================
# This file specifies the minimum required versions for Terraform and
# all providers used in this configuration. Version constraints ensure
# compatibility and prevent issues from breaking changes in newer versions.
#
# Provider versions are pinned to ensure consistent behavior across
# different environments and team members while allowing patch updates
# for security fixes and bug fixes.
# =============================================================================

terraform {
  # Specify minimum Terraform version
  # Using 1.0+ for stable features and better error messages
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # AWS Provider - Primary provider for all AWS resources
    # Using ~> 5.0 to allow patch updates while maintaining compatibility
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Random Provider - Used for generating unique resource suffixes
    # Using ~> 3.1 for stable random generation functionality
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    
    # Archive Provider - Used for creating Lambda deployment packages
    # Using ~> 2.2 for zip file creation and management
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# =============================================================================
# AWS PROVIDER CONFIGURATION
# =============================================================================
# The AWS provider configuration with default tags and region settings.
# Default tags are applied to all resources for consistent labeling
# and cost allocation across the infrastructure.

provider "aws" {
  # Default tags applied to all AWS resources
  # These tags help with resource management, cost allocation, and compliance
  default_tags {
    tags = {
      # Infrastructure management tags
      ManagedBy       = "terraform"
      Project         = "json-csv-converter"
      Component       = "serverless-data-pipeline"
      
      # Operational tags
      Environment     = var.environment
      Owner           = var.owner_email != "" ? var.owner_email : "terraform-managed"
      CostCenter      = var.cost_center != "" ? var.cost_center : "development"
      
      # Technical tags
      TerraformConfig = "simple-json-csv-converter-lambda-s3"
      CreatedDate     = formatdate("YYYY-MM-DD", timestamp())
      
      # Compliance and governance tags
      DataClass       = "internal"
      BackupPolicy    = "standard"
      MonitoringLevel = var.enable_monitoring ? "enhanced" : "basic"
    }
  }
  
  # Regional configuration (optional - uses environment or CLI default if not set)
  region = var.aws_region != "" ? var.aws_region : null
}

# =============================================================================
# RANDOM PROVIDER CONFIGURATION
# =============================================================================
# Random provider for generating unique identifiers
# No specific configuration needed - uses default settings

provider "random" {
  # No configuration needed - uses defaults
}

# =============================================================================
# ARCHIVE PROVIDER CONFIGURATION
# =============================================================================
# Archive provider for creating deployment packages
# No specific configuration needed - uses default settings

provider "archive" {
  # No configuration needed - uses defaults
}

# =============================================================================
# TERRAFORM BACKEND CONFIGURATION (OPTIONAL)
# =============================================================================
# Uncomment and configure the backend block below if you want to store
# Terraform state remotely. This is recommended for team environments
# and production deployments.

# Example S3 backend configuration:
/*
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "json-csv-converter/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    
    # Optional: Use assume role for cross-account access
    # role_arn = "arn:aws:iam::ACCOUNT-ID:role/TerraformStateRole"
  }
}
*/

# Example Terraform Cloud backend configuration:
/*
terraform {
  cloud {
    organization = "your-organization"
    workspaces {
      name = "json-csv-converter"
    }
  }
}
*/

# =============================================================================
# TERRAFORM CONFIGURATION OPTIONS
# =============================================================================
# Additional Terraform configuration options for enhanced functionality

terraform {
  # Enable experiment features if needed (use with caution)
  # experiments = []
  
  # Provider metadata for better dependency management
  provider_meta "aws" {
    module_name    = "json-csv-converter"
    module_version = "1.0.0"
  }
}

# =============================================================================
# VERSION COMPATIBILITY NOTES
# =============================================================================
# 
# AWS Provider Version Notes:
# - v5.x: Latest major version with modern resource implementations
# - Supports all AWS services used in this configuration
# - Includes enhanced security features and validation
# - Backward compatible with existing Terraform configurations
#
# Terraform Version Notes:
# - v1.0+: Stable release with guaranteed backward compatibility
# - Includes improved error messages and validation
# - Better state management and dependency resolution
# - Enhanced HCL syntax and function support
#
# Random Provider Version Notes:
# - v3.1+: Stable random generation with improved entropy
# - Consistent behavior across different platforms
# - Better integration with Terraform lifecycle management
#
# Archive Provider Version Notes:
# - v2.2+: Reliable zip file creation and hash generation
# - Proper handling of file permissions and timestamps
# - Support for various archive formats and compression
#
# =============================================================================
# UPGRADE CONSIDERATIONS
# =============================================================================
# 
# When upgrading provider versions:
# 1. Review the provider changelog for breaking changes
# 2. Test in a development environment first
# 3. Update version constraints gradually (minor versions first)
# 4. Validate all resources after upgrade
# 5. Update this documentation with any changes
#
# Common upgrade path:
# 1. aws ~> 5.0 -> ~> 5.1 -> ~> 5.2 (minor version increases)
# 2. Test each increment thoroughly
# 3. Update to next major version only after thorough testing
#
# =============================================================================