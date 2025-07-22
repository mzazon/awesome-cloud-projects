# ============================================================================
# Terraform and Provider Version Requirements
# ============================================================================
# This file defines the required versions for Terraform and all providers
# used in the Real-Time Fleet Optimization infrastructure deployment.
# Version constraints ensure compatibility and reproducible deployments.

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.5.0"

  # Provider requirements with version constraints
  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Platform Beta provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Archive provider for creating function source code archives
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Template provider for processing function templates
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }

    # Time provider for time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Optional: Terraform Cloud/Enterprise configuration
  # Uncomment and configure for remote state management
  /*
  cloud {
    organization = "your-terraform-cloud-org"
    workspaces {
      name = "fleet-optimization"
    }
  }
  */

  # Optional: Backend configuration for state storage
  # Uncomment and configure for remote state storage
  /*
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "fleet-optimization"
  }
  */
}

# ============================================================================
# Provider Configuration
# ============================================================================

# Primary Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all resources
  default_labels = merge(var.resource_labels, {
    environment     = var.environment
    managed-by      = "terraform"
    application     = "fleet-optimization"
    cost-center     = var.cost_center
    deployment-date = formatdate("YYYY-MM-DD", timestamp())
  })

  # Enable batching for better performance with large deployments
  batching {
    enable_batching = true
    send_after      = "10s"
  }

  # User project override for billing
  user_project_override = true

  # Request timeout for API calls
  request_timeout = "120s"
}

# Google Cloud Beta provider for accessing preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Inherit default labels from main provider
  default_labels = merge(var.resource_labels, {
    environment     = var.environment
    managed-by      = "terraform"
    application     = "fleet-optimization"
    cost-center     = var.cost_center
    deployment-date = formatdate("YYYY-MM-DD", timestamp())
  })

  # Enable batching for better performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }

  user_project_override = true
  request_timeout       = "120s"
}

# Random provider configuration
provider "random" {
  # No specific configuration required
}

# Archive provider configuration  
provider "archive" {
  # No specific configuration required
}

# Template provider configuration
provider "template" {
  # No specific configuration required
}

# Time provider configuration
provider "time" {
  # No specific configuration required
}

# ============================================================================
# Provider Feature Requirements
# ============================================================================

# Minimum provider versions for specific features used in this configuration:
#
# Google Provider >= 6.0.0:
# - Cloud Functions 2nd generation support
# - Enhanced Cloud Bigtable autoscaling
# - Improved Pub/Sub schema validation
# - Cloud KMS envelope encryption
# - Advanced IAM conditions
# - Cloud Monitoring alerting policies v2
# - Secret Manager integration improvements
#
# Google Beta Provider >= 6.0.0:
# - Preview Cloud Functions features
# - Beta Cloud Bigtable features
# - Advanced VPC configurations
#
# Random Provider >= 3.6.0:
# - Enhanced randomization algorithms
# - Improved state management
#
# Archive Provider >= 2.4.0:
# - Better zip file handling
# - Improved large file support
#
# Template Provider >= 2.2.0:
# - Enhanced template processing
# - Better variable interpolation
#
# Time Provider >= 0.12.0:
# - Improved time calculations
# - Better timezone handling

# ============================================================================
# Terraform Version Requirements Explanation
# ============================================================================

# Terraform >= 1.5.0 required for:
# - Enhanced provider configuration
# - Improved state management
# - Better error handling
# - Advanced variable validation
# - Optional object attributes
# - Enhanced for_each expressions
# - Improved sensitive value handling
# - Better module composition
# - Advanced lifecycle management
# - Enhanced depends_on functionality

# ============================================================================
# Provider Compatibility Matrix
# ============================================================================

# This configuration has been tested with:
# - Terraform 1.5.x through 1.8.x
# - Google Provider 6.0.x through 6.44.x
# - Google Beta Provider 6.0.x through 6.44.x
# - Random Provider 3.6.x
# - Archive Provider 2.4.x
# - Template Provider 2.2.x
# - Time Provider 0.12.x

# ============================================================================
# Upgrade Path
# ============================================================================

# When upgrading providers:
# 1. Review provider changelogs for breaking changes
# 2. Test in development environment first
# 3. Update version constraints incrementally
# 4. Run terraform plan to identify required changes
# 5. Update resource configurations as needed
# 6. Document any breaking changes for team

# ============================================================================
# Additional Provider Configuration Notes
# ============================================================================

# Google Cloud Provider Authentication Options:
# 1. Service Account Key File: Set GOOGLE_APPLICATION_CREDENTIALS
# 2. gcloud CLI: Run 'gcloud auth application-default login'
# 3. Compute Engine Metadata: Automatic when running on GCE
# 4. Workload Identity: For GKE and other managed services

# Required API Enablement:
# The following APIs must be enabled in the target project:
# - Cloud Resource Manager API
# - Cloud Billing API (if managing billing)
# - Identity and Access Management (IAM) API
# - Cloud Key Management Service (KMS) API
# - Cloud Functions API
# - Cloud Pub/Sub API
# - Cloud Bigtable API
# - Cloud Storage API
# - Cloud Monitoring API
# - Cloud Logging API
# - Secret Manager API
# - Optimization AI API (Fleet Routing)
# - Routes API (Google Maps Platform)

# These APIs are automatically enabled by the terraform configuration
# in the google_project_service resources in main.tf