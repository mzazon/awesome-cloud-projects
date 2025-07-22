# ==============================================================================
# Terraform and Provider Version Constraints
# This file defines the minimum required versions for Terraform and providers
# to ensure compatibility and feature availability.
# ==============================================================================

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5.0"

  # Required providers with version constraints
  required_providers {
    # AWS provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating random values
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Local provider for local values and file operations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }

    # Template provider for template file processing
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }

  # Backend configuration (uncomment and configure as needed)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "nested-stacks-demo/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  # }

  # Experimental features (if any)
  # experiments = []
}

# Provider configuration is handled in main.tf to avoid duplication
# The aws provider block in main.tf includes:
# - Region configuration
# - Default tags for resource management
# - Any additional provider-specific settings

# ==============================================================================
# Version Compatibility Notes
# ==============================================================================

# Terraform >= 1.5.0 is required for:
# - Enhanced import functionality
# - Improved validation functions
# - Better error messaging
# - Check blocks (if used in future)

# AWS Provider ~> 5.0 provides:
# - Latest AWS service support
# - Enhanced resource management
# - Improved drift detection
# - Better handling of AWS API changes

# Random Provider ~> 3.1 includes:
# - Improved random value generation
# - Better state management for random resources
# - Enhanced validation capabilities

# Local Provider ~> 2.1 offers:
# - Improved file handling
# - Better path resolution
# - Enhanced template processing

# Template Provider ~> 2.2 features:
# - Advanced template functions
# - Better variable substitution
# - Improved error handling for template files

# ==============================================================================
# Upgrade Path
# ==============================================================================

# When upgrading Terraform or providers:
# 1. Review CHANGELOG files for breaking changes
# 2. Test in development environment first
# 3. Update version constraints gradually
# 4. Use 'terraform plan' to review changes
# 5. Consider using 'terraform state replace-provider' if needed

# For AWS provider upgrades:
# - Check for deprecated resources or attributes
# - Review new required arguments
# - Validate import/export behavior changes
# - Test authentication and permission changes

# ==============================================================================
# Development vs Production Constraints
# ==============================================================================

# For development environments, you might use:
# - Looser version constraints for faster iteration
# - Latest provider versions for new features
# - Frequent Terraform upgrades

# For production environments, consider:
# - Stricter version pinning (e.g., "= 5.25.0")
# - Thorough testing before version updates
# - Gradual rollout of version changes
# - Documentation of version decisions