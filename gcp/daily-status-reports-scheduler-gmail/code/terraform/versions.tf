# ==============================================================================
# TERRAFORM AND PROVIDER VERSION REQUIREMENTS
# ==============================================================================
# This file defines the required versions for Terraform and all providers used
# in the daily status reports infrastructure. Version constraints ensure
# compatibility and reproducible deployments across different environments.

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Beta provider for accessing beta features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Archive provider for creating ZIP files
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random provider for generating unique suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Time provider for time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# ==============================================================================
# GOOGLE CLOUD PROVIDER CONFIGURATION
# ==============================================================================
# Configure the Google Cloud Provider with default settings

provider "google" {
  # Project and region will be set via variables or environment
  project = var.project_id
  region  = var.region

  # Default labels applied to all resources
  default_labels = merge(
    {
      environment    = var.environment
      recipe        = "daily-status-reports"
      managed-by    = "terraform"
      created-date  = formatdate("YYYY-MM-DD", timestamp())
    },
    var.additional_labels
  )

  # User project override for service usage API calls
  user_project_override = true

  # Request timeout for API calls
  request_timeout = "60s"
}

# Google Beta provider configuration for beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region

  # Default labels applied to all resources
  default_labels = merge(
    {
      environment    = var.environment
      recipe        = "daily-status-reports"
      managed-by    = "terraform"
      created-date  = formatdate("YYYY-MM-DD", timestamp())
    },
    var.additional_labels
  )

  # User project override for service usage API calls
  user_project_override = true

  # Request timeout for API calls
  request_timeout = "60s"
}

# ==============================================================================
# PROVIDER FEATURE FLAGS AND CONFIGURATION
# ==============================================================================

# Archive provider configuration
provider "archive" {
  # No specific configuration required
}

# Random provider configuration
provider "random" {
  # No specific configuration required
}

# Time provider configuration
provider "time" {
  # No specific configuration required
}

# ==============================================================================
# BACKEND CONFIGURATION (OPTIONAL)
# ==============================================================================
# Uncomment and modify the backend configuration below to store Terraform
# state in Google Cloud Storage for team collaboration and state management

/*
terraform {
  backend "gcs" {
    bucket  = "your-terraform-state-bucket"
    prefix  = "daily-status-reports"
    
    # Optional: Enable state locking with Cloud Storage
    # This requires a separate bucket for state locking
    # encryption_key = "your-encryption-key"
  }
}
*/

# Alternative: Remote backend configuration for Terraform Cloud
/*
terraform {
  cloud {
    organization = "your-organization"
    
    workspaces {
      name = "daily-status-reports-gcp"
    }
  }
}
*/

# ==============================================================================
# LOCAL VALUES AND COMPUTED CONFIGURATIONS
# ==============================================================================
# Define local values for computed configurations and resource naming

locals {
  # Common resource tags/labels
  common_labels = merge(
    {
      environment     = var.environment
      recipe         = "daily-status-reports"
      managed-by     = "terraform"
      project-id     = var.project_id
      region         = var.region
      cost-center    = var.cost_center != "" ? var.cost_center : "unassigned"
      team-owner     = var.team_owner != "" ? var.team_owner : "platform-team"
      created-date   = formatdate("YYYY-MM-DD", timestamp())
    },
    var.additional_labels
  )

  # Resource naming convention
  resource_prefix = "${var.environment}-status-reports"
  
  # Function source files location
  function_source_dir = "${path.module}/function_code"
  
  # Computed email configuration validation
  email_config_valid = (
    var.sender_email != "" &&
    var.recipient_email != "" &&
    var.sender_password != ""
  )

  # API services that need to be enabled
  required_apis = [
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com", 
    "monitoring.googleapis.com",
    "gmail.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
}

# ==============================================================================
# VERSION COMPATIBILITY NOTES
# ==============================================================================
/*
PROVIDER VERSION RATIONALE:

1. Google Provider (~> 6.0):
   - Latest stable version with comprehensive GCP service support
   - Includes all required resources for Cloud Functions, Scheduler, and IAM
   - Maintains backward compatibility for existing deployments

2. Archive Provider (~> 2.4):
   - Stable version for creating ZIP archives of function source code
   - Reliable file handling and compression capabilities

3. Random Provider (~> 3.6):
   - Latest stable version for generating unique resource suffixes
   - Ensures resource naming uniqueness across deployments

4. Time Provider (~> 0.12):
   - Used for time-based operations and delays if needed
   - Provides timestamp functions for resource labeling

TERRAFORM VERSION:
- Minimum version 1.0 ensures access to modern Terraform features
- Supports all required provider configurations and resource types
- Compatible with Terraform Cloud and enterprise features

UPGRADE PATH:
- Regular provider updates should be tested in non-production environments
- Consider pinning to specific versions for production deployments
- Review provider changelogs before upgrading across major versions
*/