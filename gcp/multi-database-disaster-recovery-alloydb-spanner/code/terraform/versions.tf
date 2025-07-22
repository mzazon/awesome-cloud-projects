# ==============================================================================
# TERRAFORM AND PROVIDER VERSION CONSTRAINTS
# ==============================================================================
# This file defines the required Terraform version and provider versions
# for the multi-database disaster recovery infrastructure. Version constraints
# ensure consistent deployments across different environments and teams.
# ==============================================================================

terraform {
  # Specify minimum Terraform version for feature compatibility
  required_version = ">= 1.6.0"

  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44.0"
    }

    # Google Beta provider for preview features (if needed)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44.0"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }

    # Time provider for time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12.0"
    }

    # Null provider for provisioners and local operations
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }

    # Archive provider for creating ZIP files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and configure for production deployments
  #
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "disaster-recovery/terraform.tfstate"
  # }
  #
  # OR for Terraform Cloud:
  #
  # cloud {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "multi-database-disaster-recovery"
  #   }
  # }
}

# ==============================================================================
# GOOGLE CLOUD PROVIDER CONFIGURATION
# ==============================================================================

# Primary Google Cloud provider configuration
provider "google" {
  # Project ID should be provided via variable or environment variable
  project = var.project_id
  
  # Default region for resources that don't specify a region
  region = var.primary_region
  
  # Default zone for resources that don't specify a zone
  zone = var.primary_zone

  # Enable request/response logging for debugging (optional)
  # request_timeout = "60s"
  
  # User project override for quota and billing (optional)
  # user_project_override = true
  
  # Additional configuration for enterprise environments
  # access_token = var.access_token
  # impersonate_service_account = var.impersonate_service_account
}

# Google Beta provider for accessing preview features
provider "google-beta" {
  # Project ID should be provided via variable or environment variable
  project = var.project_id
  
  # Default region for beta resources
  region = var.primary_region
  
  # Default zone for beta resources
  zone = var.primary_zone
}

# ==============================================================================
# PROVIDER FEATURE COMPATIBILITY NOTES
# ==============================================================================

# Google Cloud Provider v6.44.0 Feature Support:
# - AlloyDB: Full support for clusters, instances, and cross-region setups
# - Cloud Spanner: Complete support for multi-regional instances and autoscaling
# - Cloud Storage: Full support for lifecycle policies and cross-region replication
# - Cloud Functions: 2nd generation functions with enhanced networking
# - Cloud Scheduler: Full support for HTTP and Pub/Sub triggers
# - Pub/Sub: Complete messaging support with dead letter queues
# - Monitoring: Comprehensive dashboard and alerting policy support
# - IAM: Fine-grained service account and role management
# - VPC: Advanced networking features including service networking

# ==============================================================================
# TERRAFORM VERSION COMPATIBILITY
# ==============================================================================

# Terraform 1.6.0+ Features Used:
# - Enhanced variable validation with complex expressions
# - Improved provider configuration inheritance
# - Advanced lifecycle management rules
# - Native support for sensitive outputs
# - Enhanced error handling and diagnostics
# - Improved state management and locking

# ==============================================================================
# PROVIDER AUTHENTICATION CONFIGURATION
# ==============================================================================

# Authentication methods (choose one):
#
# 1. Service Account Key File (not recommended for production):
#    provider "google" {
#      credentials = file("path/to/service-account-key.json")
#      project     = var.project_id
#      region      = var.primary_region
#    }
#
# 2. Application Default Credentials (recommended):
#    Set GOOGLE_APPLICATION_CREDENTIALS environment variable
#    gcloud auth application-default login
#
# 3. Workload Identity (recommended for GKE/Cloud Build):
#    Automatically configured when running in Google Cloud environments
#
# 4. Service Account Impersonation (recommended for CI/CD):
#    provider "google" {
#      impersonate_service_account = "terraform@project-id.iam.gserviceaccount.com"
#      project                     = var.project_id
#      region                      = var.primary_region
#    }

# ==============================================================================
# PROVIDER CONFIGURATION VALIDATION
# ==============================================================================

# Validate that required APIs are enabled
# This is handled in main.tf with google_project_service resources

# Validate project permissions
# The following permissions are required for this configuration:
# - AlloyDB Admin (roles/alloydb.admin)
# - Cloud Spanner Admin (roles/spanner.admin)
# - Storage Admin (roles/storage.admin)
# - Cloud Functions Developer (roles/cloudfunctions.developer)
# - Cloud Scheduler Admin (roles/cloudscheduler.admin)
# - Pub/Sub Admin (roles/pubsub.admin)
# - Compute Network Admin (roles/compute.networkAdmin)
# - Service Account Admin (roles/iam.serviceAccountAdmin)
# - Monitoring Admin (roles/monitoring.admin)

# ==============================================================================
# PROVIDER RESOURCE QUOTAS AND LIMITS
# ==============================================================================

# Consider the following quotas when deploying:
# - AlloyDB: Regional quotas for clusters and instances
# - Cloud Spanner: Processing unit quotas per region/multi-region
# - Cloud Storage: Bucket creation and storage quotas
# - Cloud Functions: Concurrent executions and memory limits
# - Pub/Sub: Topic and subscription limits
# - Compute Engine: Network and firewall rule quotas
# - IAM: Service account and role binding limits

# Check current quotas with:
# gcloud compute project-info describe --project=PROJECT_ID

# ==============================================================================
# PROVIDER MIGRATION NOTES
# ==============================================================================

# When upgrading provider versions:
# 1. Review the provider changelog for breaking changes
# 2. Test in a development environment first
# 3. Plan the upgrade during maintenance windows
# 4. Keep backups of terraform state files
# 5. Use terraform plan to preview changes
# 6. Consider using terraform state replace-provider for major upgrades

# Migration from older provider versions:
# - v5.x to v6.x: Review resource attribute changes
# - Check for deprecated arguments and resources
# - Update any custom modules or child modules
# - Validate all data sources still work correctly

# ==============================================================================
# EXPERIMENTAL FEATURES
# ==============================================================================

# Enable experimental features if needed (use with caution in production)
# terraform {
#   experiments = [example_experiment]
# }

# ==============================================================================
# LOCAL VALUES FOR PROVIDER CONFIGURATION
# ==============================================================================

locals {
  # Common labels applied to all resources
  common_labels = merge(
    {
      managed_by        = "terraform"
      project           = var.project_id
      environment       = var.environment
      disaster_recovery = "enabled"
      created_date      = formatdate("YYYY-MM-DD", timestamp())
    },
    var.labels
  )

  # Provider configuration summary for outputs
  provider_info = {
    terraform_version     = ">=1.6.0"
    google_provider       = "~>6.44.0"
    google_beta_provider  = "~>6.44.0"
    random_provider       = "~>3.6.0"
    time_provider         = "~>0.12.0"
    null_provider         = "~>3.2.0"
    archive_provider      = "~>2.4.0"
  }
}