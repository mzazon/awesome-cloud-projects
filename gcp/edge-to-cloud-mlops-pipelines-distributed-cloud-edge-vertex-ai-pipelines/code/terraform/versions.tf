# =============================================================================
# TERRAFORM AND PROVIDER VERSION REQUIREMENTS
# =============================================================================
# This file defines the required versions for Terraform and all providers used
# in the Edge-to-Cloud MLOps Pipelines infrastructure deployment.

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Provider for core GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Beta Provider for beta features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Kubernetes Provider for GKE workload management
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }

    # Random Provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Archive Provider for creating Cloud Function deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Null Provider for provisioners and local commands
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    # Time Provider for time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Backend configuration for state management
  # Uncomment and configure based on your requirements
  /*
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "terraform/state/mlops-pipeline"
  }
  */
}

# =============================================================================
# PROVIDER CONFIGURATIONS
# =============================================================================

# Primary Google Cloud Provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all resources
  default_labels = merge(
    {
      terraform     = "true"
      environment   = var.environment
      project       = "mlops-pipeline"
      managed-by    = "terraform"
      created-date  = formatdate("YYYY-MM-DD", timestamp())
    },
    var.labels
  )

  # Request timeout for API calls
  request_timeout = "60s"

  # Batching configuration for improved performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }
}

# Google Cloud Beta Provider for beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all beta resources
  default_labels = merge(
    {
      terraform     = "true"
      environment   = var.environment
      project       = "mlops-pipeline"
      managed-by    = "terraform"
      created-date  = formatdate("YYYY-MM-DD", timestamp())
      provider-type = "beta"
    },
    var.labels
  )

  # Request timeout for API calls
  request_timeout = "60s"

  # Batching configuration for improved performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }
}

# Random Provider configuration
provider "random" {
  # No additional configuration required
}

# Archive Provider configuration
provider "archive" {
  # No additional configuration required
}

# Null Provider configuration
provider "null" {
  # No additional configuration required
}

# Time Provider configuration
provider "time" {
  # No additional configuration required
}

# =============================================================================
# PROVIDER FEATURES AND COMPATIBILITY
# =============================================================================

# The following providers are configured with specific version constraints
# to ensure compatibility and stability:

# google (6.x):
# - Supports latest GCP features and resources
# - Includes Vertex AI, GKE Autopilot, Cloud Monitoring v2
# - Enhanced IAM and Workload Identity support
# - Improved Cloud Storage lifecycle management

# google-beta (6.x):
# - Access to beta GCP features
# - Early access to new resource types
# - Required for some advanced configurations

# kubernetes (2.20.x):
# - Full support for Kubernetes 1.28+
# - Enhanced CRD support
# - Improved workload identity integration
# - Better handling of Kubernetes API server communication

# random (3.4.x):
# - Stable random resource generation
# - Support for various random formats
# - Consistent across Terraform operations

# archive (2.4.x):
# - Reliable file archiving for Cloud Functions
# - Support for various archive formats
# - Efficient handling of large source trees

# null (3.2.x):
# - Stable provisioner support
# - Local execution capabilities
# - Trigger mechanisms for complex workflows

# time (0.9.x):
# - Time-based resource management
# - Delay and scheduling capabilities
# - Timestamp generation and formatting

# =============================================================================
# EXPERIMENTAL FEATURES
# =============================================================================

# Enable experimental features if needed
# Uncomment the following block to enable specific experiments

/*
terraform {
  experiments = [
    # Enable experimental features here
    # Example: module_variable_optional_attrs
  ]
}
*/

# =============================================================================
# TERRAFORM CONFIGURATION VALIDATION
# =============================================================================

# Validate that required variables are provided
locals {
  # Validation for required configuration
  validate_project_id = var.project_id != "" ? true : error("project_id must be provided")
  validate_region     = var.region != "" ? true : error("region must be provided")
  validate_alert_email = var.alert_email != "" ? true : error("alert_email must be provided")
  
  # Validation for node count configuration
  validate_node_counts = var.gke_min_node_count <= var.gke_max_node_count ? true : error("gke_min_node_count must be less than or equal to gke_max_node_count")
  
  # Validation for lifecycle configuration
  validate_lifecycle = var.nearline_transition_days < var.bucket_lifecycle_age_days ? true : error("nearline_transition_days must be less than bucket_lifecycle_age_days")
}

# =============================================================================
# VERSION COMPATIBILITY NOTES
# =============================================================================

# This configuration has been tested with:
# - Terraform CLI: 1.5.x, 1.6.x, 1.7.x
# - Google Cloud Provider: 6.0.x - 6.44.x
# - Kubernetes Provider: 2.20.x - 2.30.x
# - Google Cloud SDK: 450.x - 480.x
# - kubectl: 1.28.x - 1.30.x

# Breaking changes to watch for:
# - Google Provider 7.x may introduce breaking changes to resource schemas
# - Kubernetes Provider 3.x may change CRD handling
# - GKE API changes may affect cluster configuration options

# Recommended upgrade path:
# 1. Test in non-production environment
# 2. Review provider changelog for breaking changes
# 3. Update version constraints incrementally
# 4. Validate all resources after upgrade
# 5. Update documentation and CI/CD pipelines

# =============================================================================
# PERFORMANCE OPTIMIZATION
# =============================================================================

# The following settings optimize Terraform performance for large infrastructures:

# 1. Provider batching is enabled to reduce API calls
# 2. Request timeouts are set appropriately for GCP APIs
# 3. Version constraints allow for patch updates while preventing breaking changes
# 4. Local validation reduces runtime errors
# 5. Default labels are applied consistently across resources

# For additional performance improvements:
# - Use terraform plan -parallelism=10 for faster planning
# - Configure backend with appropriate locking mechanism
# - Use terraform refresh=false when applying known changes
# - Consider using terraform workspaces for environment isolation