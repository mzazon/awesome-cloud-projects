# =============================================================================
# TERRAFORM VERSION CONSTRAINTS AND PROVIDER CONFIGURATION
# =============================================================================
# Provider requirements and version constraints for the multi-agent customer 
# service system with Contact Center AI Platform, Vertex AI, and Cloud Functions

terraform {
  # Terraform version constraint - require modern version with advanced features
  required_version = ">= 1.5.0"

  # Required providers with version constraints for stability and feature compatibility
  required_providers {
    # Google Cloud Provider - primary provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Beta Provider - for preview/beta features like Contact Center AI
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random Provider - for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Archive Provider - for creating ZIP files for Cloud Functions deployment
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Template Provider - for templating Cloud Function source code
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }

    # Time Provider - for time-based operations and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Backend configuration can be specified here or via CLI/environment
  # Uncomment and configure for remote state storage
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "multi-agent-customer-service"
  # }
}

# =============================================================================
# GOOGLE CLOUD PROVIDER CONFIGURATION
# =============================================================================

# Primary Google Cloud Provider configuration
provider "google" {
  # Project ID will be set via variable - no default here for security
  project = var.project_id
  region  = var.region
  zone    = var.zone != "" ? var.zone : "${var.region}-a"

  # Default labels applied to all resources created by this provider
  default_labels = {
    managed_by  = "terraform"
    environment = var.environment
    project     = "multi-agent-customer-service"
  }

  # Request timeout for API calls (useful for large deployments)
  request_timeout = "60s"

  # Retry configuration for transient failures
  request_reason = "terraform-multi-agent-customer-service"

  # User agent for tracking Terraform usage
  user_project_override = true
  billing_project       = var.project_id
}

# Google Cloud Beta Provider for preview/beta features
provider "google-beta" {
  # Use same project configuration as primary provider
  project = var.project_id
  region  = var.region
  zone    = var.zone != "" ? var.zone : "${var.region}-a"

  # Default labels for beta resources
  default_labels = {
    managed_by  = "terraform"
    environment = var.environment
    project     = "multi-agent-customer-service"
    beta_feature = "true"
  }

  # Extended timeout for beta features which may be slower
  request_timeout = "90s"
  
  # User project override for beta APIs
  user_project_override = true
  billing_project       = var.project_id
}

# =============================================================================
# RANDOM PROVIDER CONFIGURATION
# =============================================================================

# Random provider for generating unique identifiers
provider "random" {
  # No specific configuration needed for random provider
}

# =============================================================================
# ARCHIVE PROVIDER CONFIGURATION
# =============================================================================

# Archive provider for creating ZIP files for Cloud Functions
provider "archive" {
  # No specific configuration needed for archive provider
}

# =============================================================================
# TEMPLATE PROVIDER CONFIGURATION
# =============================================================================

# Template provider for Cloud Function source code templating
provider "template" {
  # No specific configuration needed for template provider
}

# =============================================================================
# TIME PROVIDER CONFIGURATION
# =============================================================================

# Time provider for time-based operations and resource delays
provider "time" {
  # No specific configuration needed for time provider
}

# =============================================================================
# PROVIDER VERSION COMPATIBILITY MATRIX
# =============================================================================

# Version compatibility notes for reference:
# 
# Google Provider v5.x:
# - Full support for Cloud Functions Gen 2
# - Enhanced Firestore native mode support
# - Vertex AI dataset and model management
# - BigQuery improved schema management
# - IAM conditional policies support
# - VPC-native container support
#
# Google Beta Provider v5.x:
# - Contact Center AI Platform (preview)
# - Advanced Vertex AI features
# - Enhanced monitoring and alerting
# - Preview machine learning operations
#
# Terraform v1.5+:
# - Enhanced for_each with sets and maps
# - Improved error handling and validation
# - Better state management for complex deployments
# - Advanced function capabilities
# - Optional object type attributes
#
# Random Provider v3.4+:
# - Improved seeding and entropy
# - Better cross-platform compatibility
# - Enhanced randomness for secure identifiers
#
# Archive Provider v2.4+:
# - Improved ZIP file creation
# - Better handling of large source trees
# - Enhanced compression options
# - Support for excluding files/patterns

# =============================================================================
# EXPERIMENTAL FEATURES
# =============================================================================

# Enable experimental features if needed
# terraform {
#   experiments = [
#     # Add experimental features here as needed
#   ]
# }

# =============================================================================
# PROVIDER AUTHENTICATION NOTES
# =============================================================================

# Authentication can be configured via:
# 
# 1. Environment Variables:
#    export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
#    export GOOGLE_PROJECT="your-project-id"
#    export GOOGLE_REGION="us-central1"
#
# 2. gcloud CLI Authentication:
#    gcloud auth application-default login
#    gcloud config set project YOUR_PROJECT_ID
#
# 3. Service Account Key (not recommended for production):
#    provider "google" {
#      credentials = file("path/to/service-account.json")
#      project     = "your-project-id"
#      region      = "us-central1"
#    }
#
# 4. Workload Identity (recommended for GKE/Cloud Build):
#    No explicit configuration needed when running in GCP with
#    appropriate service account and IAM bindings
#
# 5. Metadata Service (for Compute Engine/Cloud Shell):
#    Automatic authentication when running on GCP infrastructure

# =============================================================================
# TERRAFORM CLOUD / TERRAFORM ENTERPRISE CONFIGURATION
# =============================================================================

# If using Terraform Cloud or Terraform Enterprise, configure the backend:
# terraform {
#   cloud {
#     organization = "your-organization"
#     workspaces {
#       name = "multi-agent-customer-service"
#     }
#   }
# }

# =============================================================================
# LOCAL DEVELOPMENT OVERRIDES
# =============================================================================

# For local development, you can create a terraform.override.tf file
# to override provider settings without committing them to version control:
#
# # terraform.override.tf (not committed to git)
# provider "google" {
#   project = "your-dev-project-id"
#   region  = "us-central1"
# }

# =============================================================================
# PROVIDER PLUGIN CACHE CONFIGURATION
# =============================================================================

# To improve performance during development, configure provider plugin caching
# in your ~/.terraformrc file:
#
# plugin_cache_dir = "$HOME/.terraform.d/plugin-cache"
# disable_checkpoint = true

# =============================================================================
# DEBUGGING AND LOGGING
# =============================================================================

# For debugging provider issues, set these environment variables:
# export TF_LOG=DEBUG
# export TF_LOG_PROVIDER=DEBUG
# export TF_LOG_PATH="/tmp/terraform.log"
#
# For Google Cloud API debugging:
# export GOOGLE_OAUTH_ACCESS_TOKEN="your-token"  # For testing only
# export TF_LOG_PROVIDER_GOOGLE=DEBUG

# =============================================================================
# MIGRATION NOTES
# =============================================================================

# When upgrading provider versions:
# 1. Review the CHANGELOG for breaking changes
# 2. Test in a development environment first
# 3. Update version constraints gradually
# 4. Use terraform plan to review changes before applying
# 5. Consider using terraform state replace-provider for major version upgrades
#
# Example migration command:
# terraform state replace-provider hashicorp/google hashicorp/google

# =============================================================================
# SECURITY CONSIDERATIONS
# =============================================================================

# Security best practices for provider configuration:
# 1. Never commit service account keys to version control
# 2. Use least-privilege IAM policies for Terraform service accounts
# 3. Enable audit logging for Terraform operations
# 4. Use encrypted state storage backends
# 5. Implement proper secret management for sensitive variables
# 6. Regularly rotate service account keys
# 7. Use Workload Identity Federation when possible
# 8. Monitor Terraform operations through Cloud Audit Logs