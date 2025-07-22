# =========================================================================
# AWS EC2 Instances Securely with Systems Manager - Provider Requirements
# =========================================================================
# This file defines the Terraform and provider version requirements for
# consistent and stable infrastructure deployments.

terraform {
  # Enforce minimum Terraform version for stability and feature support
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # AWS Provider - Official HashiCorp provider for Amazon Web Services
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      
      # Version 5.x provides:
      # - Latest EC2 features and instance types
      # - Enhanced Systems Manager support
      # - Improved CloudWatch Logs integration
      # - Better IAM policy management
      # - Support for latest AWS regions and services
    }

    # Random Provider - For generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
      
      # Used for:
      # - Generating unique resource name suffixes
      # - Creating random passwords if needed
      # - Ensuring resource name uniqueness across deployments
    }

    # Local Provider - For managing local files and data processing
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
      
      # Used for:
      # - Creating user data scripts
      # - Template processing
      # - Local file management during deployment
    }

    # Template Provider - For processing template files (if needed)
    # Note: This is now integrated into the core Terraform functionality
    # but kept for compatibility with older configurations
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }

  # Optional: Backend configuration for remote state storage
  # Uncomment and configure based on your organization's requirements
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "ec2-ssm-demo/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "your-terraform-lock-table"
  # }
}

# =========================================================================
# PROVIDER CONFIGURATION
# =========================================================================

# AWS Provider Configuration
provider "aws" {
  # Default tags applied to all resources
  default_tags {
    tags = {
      # Terraform metadata
      TerraformManaged = "true"
      TerraformModule  = "ec2-instances-securely-systems-manager"
      TerraformVersion = "~> 1.0"
      
      # Recipe identification
      Recipe           = "ec2-instances-securely-systems-manager"
      RecipeVersion    = "1.2"
      
      # Infrastructure metadata
      InfrastructureAsCode = "terraform"
      Provider            = "aws"
      
      # Default operational tags
      CreatedBy    = "terraform"
      CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
      LastModified = formatdate("YYYY-MM-DD'T'hh:mm:ssZ", timestamp())
    }
  }

  # Optional: Additional provider configuration
  # Uncomment and modify based on your requirements
  
  # Region specification (can be overridden by environment variables)
  # region = "us-west-2"
  
  # Profile specification for AWS CLI credentials
  # profile = "default"
  
  # Assume role configuration for cross-account access
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT-ID:role/TerraformRole"
  #   session_name = "TerraformSession"
  # }
  
  # Skip metadata API check (useful in some CI/CD environments)
  # skip_metadata_api_check = true
  
  # Skip region validation (useful for new regions)
  # skip_region_validation = true
  
  # Skip credentials validation
  # skip_credentials_validation = false
  
  # Additional endpoints for testing or special configurations
  # endpoints {
  #   ec2 = "https://ec2.amazonaws.com"
  #   iam = "https://iam.amazonaws.com"
  #   ssm = "https://ssm.amazonaws.com"
  # }
}

# =========================================================================
# PROVIDER VERSION CONSTRAINTS EXPLANATION
# =========================================================================

# AWS Provider Version 5.x Benefits:
# - Enhanced EC2 instance type support including latest generation instances
# - Improved Systems Manager integration with new features
# - Better CloudWatch Logs resource management
# - Enhanced IAM policy validation and management
# - Support for latest AWS services and features
# - Improved error handling and debugging capabilities
# - Better resource import capabilities
# - Enhanced data source functionality

# Version Constraint Strategy:
# Using "~> 5.0" allows:
# - Automatic updates to patch versions (5.0.1, 5.0.2, etc.)
# - Automatic updates to minor versions (5.1.0, 5.2.0, etc.)
# - Prevents automatic updates to major versions (6.0.0)
# - Ensures compatibility while receiving security updates and bug fixes

# =========================================================================
# TERRAFORM BACKEND RECOMMENDATIONS
# =========================================================================

# For production deployments, consider using a remote backend:
#
# S3 Backend Benefits:
# - Remote state storage and locking
# - Team collaboration capabilities
# - State encryption and versioning
# - Integration with DynamoDB for locking
#
# Example S3 Backend Configuration:
# terraform {
#   backend "s3" {
#     bucket         = "company-terraform-state-prod"
#     key            = "aws/ec2-ssm-demo/terraform.tfstate"
#     region         = "us-west-2"
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#     
#     # Optional: Workspace-based state isolation
#     workspace_key_prefix = "workspaces"
#   }
# }

# Alternative Backend Options:
# - Terraform Cloud: terraform { cloud { organization = "company" } }
# - Azure Backend: terraform { backend "azurerm" { ... } }
# - Google Cloud Backend: terraform { backend "gcs" { ... } }
# - Consul Backend: terraform { backend "consul" { ... } }

# =========================================================================
# COMPATIBILITY MATRIX
# =========================================================================

# Terraform Version Compatibility:
# - 1.0.x: Minimum supported version with stable features
# - 1.1.x: Enhanced provider dependency management
# - 1.2.x: Improved configuration language features
# - 1.3.x: Better error messages and debugging
# - 1.4.x: Enhanced state management capabilities
# - 1.5.x: Latest features and improvements

# AWS Provider Compatibility:
# - 4.x: Legacy support for older configurations
# - 5.x: Current recommended version with latest features
# - 6.x: Future version (when available)

# Operating System Support:
# This configuration supports:
# - Amazon Linux 2023 (AL2023)
# - Ubuntu 22.04 LTS (Jammy Jellyfish)
# - Additional OS support can be added via variables

# =========================================================================
# UPGRADE CONSIDERATIONS
# =========================================================================

# When upgrading provider versions:
# 1. Review the provider changelog for breaking changes
# 2. Test in a development environment first
# 3. Update terraform.lock.hcl file
# 4. Run terraform plan to review changes
# 5. Consider using terraform state replace-provider if needed

# Commands for version management:
# - terraform version                    # Check current versions
# - terraform providers                  # List provider requirements
# - terraform providers lock             # Update lock file
# - terraform init -upgrade             # Upgrade to latest allowed versions