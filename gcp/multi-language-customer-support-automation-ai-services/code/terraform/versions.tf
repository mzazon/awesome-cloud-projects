# Terraform and Provider Version Requirements
# This file specifies the minimum versions required for Terraform and all providers

terraform {
  # Require Terraform version 1.0 or higher for stable features
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # Google Cloud Platform provider for core GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Platform Beta provider for beta features and newer resources
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Archive provider for creating zip files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Time provider for time-based operations (if needed for delays)
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }

  # Optional: Configure backend for remote state storage
  # Uncomment and modify the backend configuration below for production use
  
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "multilingual-support/state"
  # }
  
  # Alternative backend options:
  # 
  # backend "local" {
  #   path = "terraform.tfstate"
  # }
  #
  # backend "http" {
  #   address        = "https://your-state-backend.example.com/terraform/state"
  #   lock_address   = "https://your-state-backend.example.com/terraform/lock"
  #   unlock_address = "https://your-state-backend.example.com/terraform/unlock"
  # }

  # Experimental features (if needed)
  # experiments = []
}

# Provider feature blocks for controlling provider behavior
provider_meta "google" {
  # Set the module name for tracking in GCP APIs
  module_name = "terraform-gcp-multilingual-support/v1.0.0"
}

provider_meta "google-beta" {
  # Set the module name for tracking in GCP APIs
  module_name = "terraform-gcp-multilingual-support-beta/v1.0.0"
}

# Terraform Cloud/Enterprise configuration (if using)
# terraform {
#   cloud {
#     organization = "your-organization"
#     workspaces {
#       tags = ["gcp", "ai-services", "customer-support"]
#     }
#   }
# }

# Version constraints explanation:
# 
# google ~> 6.0:
# - Allows versions 6.0.0 through 6.x.x (but not 7.0.0)
# - Provides stable GCP resource management with latest features
# - Includes support for Cloud Functions 2nd generation, Workflows, and latest AI APIs
#
# google-beta ~> 6.0:
# - Same versioning as google provider
# - Provides access to beta GCP features and resources
# - Required for some newer AI services and advanced configurations
#
# archive ~> 2.4:
# - Allows versions 2.4.0 through 2.x.x
# - Provides stable file archiving capabilities for Cloud Functions deployment
#
# random ~> 3.6:
# - Allows versions 3.6.0 through 3.x.x
# - Provides cryptographically secure random number generation
# - Used for creating unique resource identifiers
#
# time ~> 0.11:
# - Allows versions 0.11.0 through 0.x.x
# - Provides time-based resources and data sources
# - Useful for creating delays between resource deployments if needed

# Minimum provider feature requirements:
# - Google Provider 6.0+ includes:
#   * Cloud Functions 2nd generation support
#   * Enhanced Firestore management
#   * Latest Cloud Monitoring and Logging features
#   * Improved IAM and service account management
#   * Support for latest AI/ML service configurations
#
# - Google Beta Provider 6.0+ includes:
#   * Preview features for AI services
#   * Advanced Firestore configurations
#   * Beta monitoring and alerting features
#   * Early access to new GCP services

# Provider configuration notes:
# 1. The google provider handles most GCP resources
# 2. The google-beta provider is used for newer or beta features
# 3. Archive provider creates zip files for Cloud Function source code
# 4. Random provider generates unique suffixes for resource names
# 5. Time provider can add delays between resource creation if needed

# State management recommendations:
# 1. Use remote state backend (GCS, Terraform Cloud, etc.) for team collaboration
# 2. Enable state locking to prevent concurrent modifications
# 3. Use state encryption for sensitive data protection
# 4. Implement state backup strategies for disaster recovery
# 5. Consider using workspaces for multiple environments

# Version update strategy:
# 1. Test provider updates in development environment first
# 2. Review provider changelogs before updating
# 3. Update minor versions regularly for bug fixes and new features
# 4. Plan major version updates carefully with thorough testing
# 5. Pin to specific versions for production environments if needed