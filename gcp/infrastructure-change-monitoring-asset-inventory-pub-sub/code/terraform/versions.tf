# ==============================================================================
# Terraform and Provider Version Requirements
# ==============================================================================
# This file defines the minimum required versions for Terraform and all
# providers used in the infrastructure change monitoring solution to ensure
# compatibility and access to required features.

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.5.0"
  
  # Required provider configurations with version constraints
  required_providers {
    # Google Cloud Provider - Primary provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44.0"
    }
    
    # Google Cloud Beta Provider - For beta features and services
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44.0"
    }
    
    # Random Provider - For generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    
    # Archive Provider - For creating function deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }
    
    # Time Provider - For time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11.0"
    }
  }
}

# ==============================================================================
# Provider Configuration
# ==============================================================================

# Primary Google Cloud Provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  
  # Default labels applied to all resources created by this provider
  default_labels = {
    managed_by  = "terraform"
    environment = var.environment
    component   = "infrastructure-monitoring"
  }
  
  # Enable user project override for quota and billing
  user_project_override = true
  
  # Request timeout configuration for API calls
  request_timeout = "60s"
}

# Google Cloud Beta Provider for beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  
  # Default labels applied to all resources created by this provider
  default_labels = {
    managed_by  = "terraform"
    environment = var.environment
    component   = "infrastructure-monitoring"
  }
  
  # Enable user project override for quota and billing
  user_project_override = true
  
  # Request timeout configuration for API calls
  request_timeout = "60s"
}

# Random provider configuration
provider "random" {
  # No specific configuration required
}

# Archive provider configuration
provider "archive" {
  # No specific configuration required
}

# Time provider configuration
provider "time" {
  # No specific configuration required
}

# ==============================================================================
# Terraform Backend Configuration
# ==============================================================================
# Uncomment and configure the backend block below to store Terraform state
# in Google Cloud Storage for team collaboration and state locking.

# terraform {
#   backend "gcs" {
#     bucket  = "your-terraform-state-bucket"
#     prefix  = "infrastructure-monitoring"
#     
#     # Optional: Enable state locking with Cloud Storage
#     # encryption_key = "your-encryption-key"
#   }
# }

# ==============================================================================
# Required APIs
# ==============================================================================
# The following Google Cloud APIs must be enabled in the target project:
# 
# - cloudasset.googleapis.com          (Cloud Asset Inventory API)
# - pubsub.googleapis.com              (Cloud Pub/Sub API)
# - cloudfunctions.googleapis.com      (Cloud Functions API)
# - bigquery.googleapis.com            (BigQuery API)
# - monitoring.googleapis.com          (Cloud Monitoring API)
# - storage-api.googleapis.com         (Cloud Storage API)
# - iam.googleapis.com                 (Identity and Access Management API)
# - cloudresourcemanager.googleapis.com (Cloud Resource Manager API)
# - serviceusage.googleapis.com        (Service Usage API)
# - logging.googleapis.com             (Cloud Logging API)
#
# These APIs can be enabled using the following gcloud commands:
#
# gcloud services enable cloudasset.googleapis.com \
#   pubsub.googleapis.com \
#   cloudfunctions.googleapis.com \
#   bigquery.googleapis.com \
#   monitoring.googleapis.com \
#   storage-api.googleapis.com \
#   iam.googleapis.com \
#   cloudresourcemanager.googleapis.com \
#   serviceusage.googleapis.com \
#   logging.googleapis.com \
#   --project=YOUR_PROJECT_ID

# ==============================================================================
# Version Compatibility Matrix
# ==============================================================================
# This configuration has been tested with the following component versions:
#
# Component                 | Minimum Version | Tested Version
# --------------------------|-----------------|---------------
# Terraform                | 1.5.0          | 1.6.x
# Google Provider          | 6.44.0         | 6.44.0
# Google Beta Provider     | 6.44.0         | 6.44.0
# Random Provider          | 3.6.0          | 3.6.x
# Archive Provider         | 2.4.0          | 2.4.x
# Time Provider            | 0.11.0         | 0.11.x
#
# Cloud Function Runtime   | python39       | python39
# BigQuery API Version     | v2             | v2
# Pub/Sub API Version      | v1             | v1
# Asset Inventory API      | v1             | v1
# Monitoring API Version   | v3             | v3

# ==============================================================================
# Breaking Changes and Migration Notes
# ==============================================================================
# When upgrading provider versions, please review the following:
#
# Google Provider v6.x Changes:
# - Updated default behavior for certain resource configurations
# - Enhanced support for Cloud Asset Inventory features
# - Improved error handling and validation
#
# Terraform 1.5+ Features Used:
# - Enhanced provider configuration blocks
# - Improved validation functions
# - Better error messages and debugging
#
# Migration from earlier versions:
# - Review any custom provider configurations
# - Test in non-production environment first
# - Check for deprecated resource arguments
# - Validate all outputs still function correctly

# ==============================================================================
# Security and Compliance Notes
# ==============================================================================
# This configuration follows security best practices:
#
# 1. Minimum required provider versions for security patches
# 2. Explicit version constraints to prevent unexpected changes
# 3. User project override enabled for proper quota management
# 4. Request timeouts configured to prevent hanging operations
# 5. Default labels for resource organization and cost tracking
#
# For production deployments:
# - Enable Terraform state encryption
# - Use remote state storage with versioning
# - Implement state locking mechanisms
# - Regular provider version updates for security patches
# - Monitor for provider security advisories