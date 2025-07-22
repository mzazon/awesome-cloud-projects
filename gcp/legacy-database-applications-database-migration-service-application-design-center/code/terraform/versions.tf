# ===================================================
# Terraform and Provider Version Constraints
# ===================================================

terraform {
  # Minimum required Terraform version
  required_version = ">= 1.5.0"

  # Required providers with version constraints
  required_providers {
    # Google Cloud Provider
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Beta Provider (for preview features)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Random provider for generating secure values
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Time provider for resource timing
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Optional: Remote state backend configuration
  # Uncomment and configure for production use
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "legacy-database-migration"
  # }
}

# ===================================================
# Provider Configuration
# ===================================================

# Default Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels for all resources created by this provider
  default_labels = {
    terraform      = "true"
    environment    = var.environment
    recipe         = "legacy-database-migration"
    cost-center    = var.cost_center
    owner          = var.owner
  }

  # User project override for billing
  user_project_override = true

  # Request timeout settings
  request_timeout = "60s"

  # Custom request headers (optional)
  # request_reason = "Legacy database migration infrastructure deployment"
}

# Google Cloud Beta provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels for all beta resources
  default_labels = {
    terraform      = "true"
    environment    = var.environment
    recipe         = "legacy-database-migration"
    provider-type  = "beta"
    cost-center    = var.cost_center
    owner          = var.owner
  }

  # User project override for billing
  user_project_override = true

  # Request timeout settings
  request_timeout = "60s"
}

# Random provider configuration
provider "random" {
  # No specific configuration needed
}

# Time provider configuration
provider "time" {
  # No specific configuration needed
}

# ===================================================
# Data Sources for Provider Information
# ===================================================

# Get current provider configuration for validation
data "google_client_config" "current" {}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Get available regions for validation
data "google_compute_regions" "available" {}

# Get available zones for the selected region
data "google_compute_zones" "available" {
  region = var.region
}

# ===================================================
# Provider Feature Validation
# ===================================================

# Check if required APIs can be enabled (validation)
data "google_project_service" "required_services" {
  for_each = toset([
    "sqladmin.googleapis.com",
    "datamigration.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
}

# ===================================================
# Local Values for Provider Configuration
# ===================================================

locals {
  # Provider validation
  provider_info = {
    terraform_version = "Use 'terraform version' to check"
    google_provider   = "~> 6.0"
    project_id       = var.project_id
    project_number   = data.google_project.current.number
    region           = var.region
    zone             = var.zone
    available_zones  = data.google_compute_zones.available.names
  }

  # API enablement status
  api_status = {
    for service in [
      "sqladmin.googleapis.com",
      "datamigration.googleapis.com", 
      "compute.googleapis.com",
      "servicenetworking.googleapis.com"
    ] : service => "Check with: gcloud services list --enabled --filter='name:${service}'"
  }
}

# ===================================================
# Version Compatibility Notes
# ===================================================

# This configuration is compatible with:
# - Terraform >= 1.5.0
# - Google Provider >= 6.0.0
# - Google Beta Provider >= 6.0.0
# - Random Provider >= 3.6.0
# - Time Provider >= 0.12.0

# Breaking changes to monitor:
# - Google Provider major version updates
# - Database Migration Service API changes
# - Cloud SQL API deprecations
# - Terraform language changes

# Recommended upgrade path:
# 1. Test in development environment first
# 2. Review provider changelogs
# 3. Update version constraints gradually
# 4. Validate all resources after upgrade

# ===================================================
# Experimental Features
# ===================================================

# Enable experimental features if needed
# terraform {
#   experiments = [
#     # List experimental features here if needed
#   ]
# }

# ===================================================
# Provider Configuration Validation
# ===================================================

# Validate that the project exists and is accessible
check "project_validation" {
  assert {
    condition     = data.google_project.current.project_id == var.project_id
    error_message = "Project ID ${var.project_id} does not match the configured project."
  }
}

# Validate that the region is available
check "region_validation" {
  assert {
    condition     = contains(data.google_compute_regions.available.names, var.region)
    error_message = "Region ${var.region} is not available in this project."
  }
}

# Validate that the zone is available in the selected region
check "zone_validation" {
  assert {
    condition     = contains(data.google_compute_zones.available.names, var.zone)
    error_message = "Zone ${var.zone} is not available in region ${var.region}."
  }
}

# ===================================================
# Required Permissions Documentation
# ===================================================

# The following IAM roles are required for the service account
# or user running this Terraform configuration:
#
# Core Infrastructure:
# - roles/compute.networkAdmin (for VPC and firewall management)
# - roles/servicenetworking.networksAdmin (for private services access)
# - roles/serviceusage.serviceUsageAdmin (for API enablement)
#
# Cloud SQL:
# - roles/cloudsql.admin (for Cloud SQL instance management)
# - roles/cloudsql.client (for connection profile creation)
#
# Database Migration Service:
# - roles/datamigration.admin (for migration job management)
# - roles/datamigration.editor (for connection profile management)
#
# Application Development:
# - roles/source.admin (for source repository management)
# - roles/aiplatform.user (for Gemini Code Assist)
#
# Monitoring and Logging:
# - roles/monitoring.editor (for alerting and metrics)
# - roles/logging.admin (for log sink management)
# - roles/storage.admin (for log storage bucket)
#
# Security:
# - roles/iam.serviceAccountUser (for service account usage)
# - roles/resourcemanager.projectIamAdmin (for IAM binding creation)

# ===================================================
# Terraform State Considerations
# ===================================================

# For production deployments, consider:
# 1. Using a remote backend (GCS bucket) for state storage
# 2. Enabling state locking with Cloud Storage
# 3. Encrypting the state file
# 4. Implementing state file backup and versioning
# 5. Restricting access to the state bucket

# Example GCS backend configuration:
# terraform {
#   backend "gcs" {
#     bucket                      = "your-terraform-state-bucket"
#     prefix                      = "environments/production/legacy-migration"
#     impersonate_service_account = "terraform@your-project.iam.gserviceaccount.com"
#   }
# }