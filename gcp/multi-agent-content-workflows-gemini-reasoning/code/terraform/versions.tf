# =============================================================================
# Provider and Terraform Version Requirements
# =============================================================================
# This file defines the required Terraform version and provider versions
# for the GCP Multi-Agent Content Workflows infrastructure.
# =============================================================================

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5.0"
  
  # Required provider versions and sources
  required_providers {
    # Google Cloud Provider - Primary provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.11.0"
    }
    
    # Google Cloud Beta Provider - For accessing beta/preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.11.0"
    }
    
    # Random Provider - For generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    
    # Archive Provider - For creating ZIP archives of Cloud Function source
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }
    
    # Time Provider - For time-based resource management
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10.0"
    }
  }
  
  # Optional: Configure remote state backend
  # Uncomment and configure for production deployments
  /*
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "multi-agent-content-workflows"
  }
  */
}

# Provider feature configurations
# -----------------------------------------------------------------------------

# Configure Google Cloud Provider with organization-level settings
provider "google" {
  # Project and region are configured via variables
  project = var.project_id
  region  = var.region
  
  # Default labels applied to all resources created by this provider
  default_labels = var.labels
  
  # Request timeout configuration
  request_timeout = "60s"
  
  # Batching configuration for improved performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }
}

# Configure Google Cloud Beta Provider for preview features
provider "google-beta" {
  # Project and region are configured via variables
  project = var.project_id
  region  = var.region
  
  # Default labels applied to all resources created by this provider
  default_labels = var.labels
  
  # Request timeout configuration
  request_timeout = "60s"
  
  # Batching configuration for improved performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }
}

# Terraform Cloud/Enterprise Configuration (Optional)
# -----------------------------------------------------------------------------
# Uncomment and configure for Terraform Cloud or Enterprise deployments
/*
terraform {
  cloud {
    organization = "your-organization"
    workspaces {
      name = "multi-agent-content-workflows"
    }
  }
}
*/

# Provider Version Constraints Documentation
# -----------------------------------------------------------------------------
# Google Provider v5.11.x includes:
# - Vertex AI Gemini 2.5 Pro support
# - Cloud Workflows v2 API support
# - Cloud Functions 2nd generation support
# - Enhanced IAM and security features
# - Improved error handling and retry logic
#
# Google Beta Provider v5.11.x includes:
# - Preview features for AI/ML services
# - Advanced Vertex AI configurations
# - Beta Cloud Workflows features
# - Experimental monitoring capabilities
#
# Random Provider v3.6.x includes:
# - Improved entropy sources
# - Better cross-platform support
# - Enhanced state management
#
# Archive Provider v2.4.x includes:
# - Support for various compression formats
# - Improved file handling
# - Better error reporting for malformed archives
#
# Time Provider v0.10.x includes:
# - Precise time-based resource management
# - Improved timezone handling
# - Better integration with other providers

# Minimum Provider Feature Requirements
# -----------------------------------------------------------------------------
# This configuration requires the following minimum API versions:
# - Vertex AI API v1 (for Gemini 2.5 Pro)
# - Cloud Workflows API v1 (for workflow orchestration)
# - Cloud Functions API v2 (for 2nd generation functions)
# - Cloud Storage API v1 (for bucket and object management)
# - IAM API v1 (for service account management)
# - Cloud Monitoring API v3 (for alerting and metrics)
# - Pub/Sub API v1 (for messaging and notifications)
# - Eventarc API v1 (for event-driven triggers)
# - Speech-to-Text API v1 (for audio processing)
# - Vision API v1 (for image analysis)
# - Data Loss Prevention API v2 (for sensitive data detection)

# Provider Upgrade Path
# -----------------------------------------------------------------------------
# When upgrading providers:
# 1. Review the CHANGELOG for breaking changes
# 2. Test in a development environment first
# 3. Update version constraints gradually (major.minor only)
# 4. Validate all resources after upgrade
# 5. Update documentation and training materials
#
# Example upgrade process:
# Current: "~> 5.11.0" (allows 5.11.x)
# Next:    "~> 5.12.0" (allows 5.12.x)
# Future:  "~> 6.0.0"  (major version upgrade)

# State Management Recommendations
# -----------------------------------------------------------------------------
# For production deployments, configure remote state:
# 1. Create a dedicated GCS bucket for Terraform state
# 2. Enable bucket versioning and lifecycle management
# 3. Configure appropriate IAM permissions
# 4. Use state locking with Cloud Storage
# 5. Implement backup and recovery procedures
#
# Example GCS backend configuration:
# terraform {
#   backend "gcs" {
#     bucket                      = "your-terraform-state-bucket"
#     prefix                      = "environments/production/multi-agent-workflows"
#     impersonate_service_account = "terraform@your-project.iam.gserviceaccount.com"
#   }
# }