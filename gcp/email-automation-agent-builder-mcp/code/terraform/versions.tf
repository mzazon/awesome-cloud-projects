# Terraform and Provider Version Requirements
# This file specifies the required versions for Terraform and all providers

terraform {
  # Require Terraform version 1.5 or later for stable features
  required_version = ">= 1.5"
  
  # Required providers with version constraints
  required_providers {
    # Google Cloud Provider for main GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Cloud Beta Provider for preview features and resources
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Archive provider for creating function source code archives
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
  
  # Optional: Configure remote state backend
  # Uncomment and configure for production deployments
  #
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "email-automation/terraform.tfstate"
  # }
  
  # Enable provider-specific features
  provider_meta "google" {
    module_name = "email-automation-recipe"
  }
  
  # Experimental features (if needed)
  # experiments = []
}

# Configure Google Cloud provider with default settings
provider "google" {
  # Project and region are set via variables
  # Additional provider configuration can be added here
  
  # Enable request/response logging for debugging (disable in production)
  # request_timeout = "60s"
  
  # User project override for billing (useful for shared VPC scenarios)
  # user_project_override = true
  
  # Default labels applied to all resources created by this provider
  # default_labels = {
  #   terraform_managed = "true"
  #   recipe_name       = "email-automation-agent-builder-mcp"
  # }
}

# Configure Google Cloud Beta provider for preview features
provider "google-beta" {
  # Inherits configuration from google provider
  # Used for resources that require beta provider features
  
  # User project override for billing
  # user_project_override = true
}

# Provider configuration for Random provider
provider "random" {
  # Random provider typically requires no additional configuration
}

# Provider configuration for Archive provider  
provider "archive" {
  # Archive provider typically requires no additional configuration
}

# Version constraints explanation:
#
# "~> 5.0" - Accepts version 5.0 and any newer minor version (5.1, 5.2, etc.)
#            but not 6.0. This is the "pessimistic constraint" operator.
#
# ">= 1.5" - Accepts version 1.5 or any newer version. Used for Terraform
#            to ensure we have access to required language features.
#
# "~> 3.6" - Accepts version 3.6 and newer patch versions (3.6.1, 3.6.2)
#            and minor versions (3.7, 3.8) but not 4.0.
#
# "~> 2.4" - Similar pattern for the archive provider.

# Notes on provider versions:
#
# 1. Google Provider v5.x includes:
#    - Cloud Functions 2nd generation support
#    - Enhanced Vertex AI integration
#    - Improved Secret Manager resources
#    - Updated IAM and security features
#
# 2. Google Beta Provider v5.x provides:
#    - Preview features for Vertex AI Agent Builder
#    - Beta APIs for advanced Cloud Functions configurations
#    - Experimental IAM and security features
#
# 3. Random Provider v3.6+ includes:
#    - Improved random generation algorithms
#    - Better state management for random values
#    - Enhanced validation features
#
# 4. Archive Provider v2.4+ includes:
#    - Better handling of file permissions
#    - Improved ZIP file creation
#    - Enhanced template file support

# Terraform version requirements:
#
# - Terraform 1.5+ is required for:
#   - Stable foreach and count functionality
#   - Enhanced variable validation
#   - Improved error handling and debugging
#   - Better provider dependency management
#   - Support for check blocks (if used)
#
# For production deployments, consider:
#
# 1. Pinning to specific provider versions instead of using ranges
# 2. Using a remote state backend (GCS bucket recommended for GCP)
# 3. Enabling provider logging and debugging features
# 4. Setting up provider aliases for multi-region deployments
# 5. Configuring provider default tags/labels for resource management

# Example of pinned versions for production:
#
# terraform {
#   required_version = "= 1.6.0"
#   
#   required_providers {
#     google = {
#       source  = "hashicorp/google"
#       version = "= 5.8.0"
#     }
#     google-beta = {
#       source  = "hashicorp/google-beta"
#       version = "= 5.8.0"
#     }
#     random = {
#       source  = "hashicorp/random"
#       version = "= 3.6.0"
#     }
#     archive = {
#       source  = "hashicorp/archive"
#       version = "= 2.4.1"
#     }
#   }
# }