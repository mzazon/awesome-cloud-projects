# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers
# used in the Real-Time Analytics Dashboards with Datastream and Looker Studio recipe

terraform {
  # Minimum Terraform version required
  # Using 1.0+ for stable features and provider configurations
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # Google Cloud provider for primary GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Beta provider for preview/beta features
    # Required for some advanced Datastream and BigQuery features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Local provider for creating local files (SQL views)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }

    # Time provider for time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Optional: Configure Terraform Cloud or remote state backend
  # Uncomment and configure as needed for your environment
  
  # cloud {
  #   organization = "your-terraform-cloud-org"
  #   workspaces {
  #     name = "gcp-real-time-analytics"
  #   }
  # }

  # Alternative: Configure GCS backend for state storage
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "real-time-analytics-dashboards"
  # }
}

# Configure the default Google Cloud provider
provider "google" {
  # Project and region can be set via variables or environment variables
  project = var.project_id
  region  = var.region

  # Default labels applied to all resources created by this provider
  default_labels = {
    environment    = var.environment
    managed-by     = "terraform"
    terraform-module = "real-time-analytics-dashboards"
    created-by     = "gcp-recipe"
  }

  # Request timeout for API operations
  request_timeout = "60s"

  # Retry configuration for API calls
  request_reason = "terraform-deployment"
}

# Configure the Google Cloud Beta provider for preview features
provider "google-beta" {
  # Project and region configuration
  project = var.project_id
  region  = var.region

  # Default labels for beta resources
  default_labels = {
    environment    = var.environment
    managed-by     = "terraform"
    terraform-module = "real-time-analytics-dashboards"
    created-by     = "gcp-recipe"
    provider-type  = "beta"
  }

  # Request configuration
  request_timeout = "60s"
  request_reason = "terraform-beta-deployment"
}

# Configure the Random provider
provider "random" {
  # No specific configuration needed for random provider
}

# Configure the Local provider
provider "local" {
  # No specific configuration needed for local provider
}

# Configure the Time provider
provider "time" {
  # No specific configuration needed for time provider
}

# Provider feature flags and experimental features
# These settings enable specific provider capabilities

# Enable user project override for API calls
# This allows API calls to be billed to the user's project
# instead of the service project
provider "google" {
  alias = "user_project_override"
  
  project = var.project_id
  region  = var.region
  
  user_project_override = true
  billing_project       = var.project_id

  default_labels = {
    environment       = var.environment
    managed-by        = "terraform"
    terraform-module  = "real-time-analytics-dashboards"
    billing-override  = "enabled"
  }
}

# Provider for impersonated service account (if needed)
# Uncomment if using service account impersonation
# provider "google" {
#   alias = "impersonated"
#   
#   project = var.project_id
#   region  = var.region
#   
#   scopes = [
#     "https://www.googleapis.com/auth/cloud-platform",
#     "https://www.googleapis.com/auth/bigquery",
#     "https://www.googleapis.com/auth/datastore"
#   ]
#   
#   # Service account to impersonate
#   impersonate_service_account = "terraform-sa@${var.project_id}.iam.gserviceaccount.com"
# }

# Data sources for provider version validation
data "google_client_config" "current" {}

data "google_client_openid_userinfo" "current" {}

# Output provider version information for troubleshooting
locals {
  provider_versions = {
    google_provider_version = data.google_client_config.current.access_token != "" ? "authenticated" : "not-authenticated"
    terraform_version      = ">=1.0"
    google_version         = "~>5.0"
    random_version         = "~>3.1"
    local_version          = "~>2.1"
    time_version           = "~>0.9"
  }
}

# Provider configuration validation
# These checks ensure providers are properly configured

# Validate Google Cloud authentication
data "google_project" "validation" {
  project_id = var.project_id
}

# Validate region availability
data "google_compute_regions" "available" {}

locals {
  # Validate that the specified region is available
  region_validation = contains(data.google_compute_regions.available.names, var.region)
}

# Custom validation rules for provider configuration
check "provider_validation" {
  assert {
    condition     = local.region_validation
    error_message = "The specified region '${var.region}' is not available in Google Cloud."
  }
}

# Provider-specific experimental features
# Enable experimental features as needed

# terraform {
#   experiments = [
#     # Enable experimental features here if needed
#     # Example: module_variable_optional_attrs
#   ]
# }

# Provider deprecation warnings and migration notes
# Document any deprecated features or migration requirements

/*
MIGRATION NOTES:
- Google Provider v5.x includes breaking changes from v4.x
- Datastream resources require explicit dependency management
- BigQuery datasets now use different default permissions
- Random provider v3.x has improved state management

DEPRECATED FEATURES:
- google_project_service.disable_on_destroy is deprecated
- Use disable_dependent_services instead

SECURITY CONSIDERATIONS:
- Always use least privilege IAM roles
- Enable audit logging for compliance
- Use encrypted connections for all data sources
- Regularly rotate service account keys
*/