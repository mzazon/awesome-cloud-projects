# =============================================================================
# TERRAFORM AND PROVIDER VERSION REQUIREMENTS
# =============================================================================
# This file defines the minimum required versions for Terraform and providers
# to ensure compatibility and access to the latest features used in this
# configuration.
# =============================================================================

terraform {
  # Require Terraform version 1.0 or higher for stable features
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # Google Cloud Platform Provider
    # Provides resources for Google Cloud services
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Platform Beta Provider
    # Provides access to beta features and services
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random Provider
    # Used for generating unique suffixes and random values
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Archive Provider
    # Used for creating ZIP archives of Cloud Function source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Null Provider
    # Used for local provisioners and external data sources if needed
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and configure for production deployments
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "database-maintenance-automation"
  # }
}

# =============================================================================
# PROVIDER CONFIGURATIONS
# =============================================================================

# Default Google Cloud Provider Configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Optional: Configure default labels for all resources
  default_labels = {
    managed_by    = "terraform"
    project       = "database-maintenance-automation"
    environment   = var.environment
  }
}

# Google Cloud Beta Provider Configuration
# Used for accessing beta features and services
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Optional: Configure default labels for all resources
  default_labels = {
    managed_by    = "terraform"
    project       = "database-maintenance-automation"
    environment   = var.environment
  }
}

# Random Provider Configuration
provider "random" {
  # No specific configuration required
}

# Archive Provider Configuration
provider "archive" {
  # No specific configuration required
}

# Null Provider Configuration
provider "null" {
  # No specific configuration required
}

# =============================================================================
# TERRAFORM CLOUD / ENTERPRISE CONFIGURATION (Optional)
# =============================================================================
# Uncomment and configure if using Terraform Cloud or Terraform Enterprise

# terraform {
#   cloud {
#     organization = "your-organization"
#     workspaces {
#       name = "database-maintenance-automation"
#     }
#   }
# }

# =============================================================================
# LOCAL VALUES FOR PROVIDER FEATURES
# =============================================================================

# Local values to track provider capabilities and features used
locals {
  provider_features_used = {
    google_sql_database_instance    = "5.0+"
    google_cloudfunctions_function  = "5.0+"
    google_cloud_scheduler_job      = "5.0+"
    google_monitoring_alert_policy  = "5.0+"
    google_monitoring_dashboard     = "5.0+"
    google_storage_bucket          = "5.0+"
    google_project_service         = "5.0+"
    google_service_account         = "5.0+"
    google_project_iam_member      = "5.0+"
  }

  # Track which beta features are used (if any)
  beta_features_used = {
    # Add any beta features used in this configuration
    # example_beta_feature = "Description of beta feature usage"
  }
}

# =============================================================================
# VERSION COMPATIBILITY NOTES
# =============================================================================
/*
Version Compatibility Notes:

Terraform Version:
- Minimum required: 1.0.0
- Tested with: 1.6.x, 1.7.x
- Recommended: Latest stable version

Google Provider Version:
- Minimum required: 5.0.0
- Tested with: 5.10.x
- Features used:
  * Cloud SQL with insights configuration
  * Cloud Functions (1st gen)
  * Cloud Scheduler with OIDC authentication
  * Cloud Monitoring alert policies and dashboards
  * Cloud Storage with lifecycle management
  * IAM service accounts and bindings

Google-Beta Provider Version:
- Minimum required: 5.0.0
- Used for: Advanced monitoring features (if needed)

Random Provider Version:
- Minimum required: 3.4.0
- Used for: Generating unique resource suffixes

Archive Provider Version:
- Minimum required: 2.4.0
- Used for: Creating Cloud Function deployment packages

Breaking Changes to Watch:
- Google Provider 5.x: Updated resource schemas for some services
- Cloud Functions: Migration to 2nd gen functions in future versions
- Cloud SQL: Changes to backup configuration schema
- Cloud Monitoring: Updates to alerting policy schema

Upgrade Path:
1. Test with new provider versions in non-production environment
2. Review provider changelogs for breaking changes
3. Update version constraints gradually
4. Validate all resources after upgrade
*/