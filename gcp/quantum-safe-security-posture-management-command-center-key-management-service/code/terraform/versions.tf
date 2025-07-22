# ============================================================================
# Terraform and Provider Version Constraints
# ============================================================================
# This file defines the required Terraform version and provider versions
# for the quantum-safe security posture management infrastructure.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Platform Beta provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Archive provider for creating ZIP files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random provider for generating unique identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }

    # Time provider for time-based operations and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }

    # Null provider for executing local commands and provisioners
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Configure backend for state management
  # Uncomment and configure based on your state management requirements
  
  # Remote state backend using Google Cloud Storage
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "quantum-security/terraform.tfstate"
  # }

  # Alternative: Terraform Cloud backend
  # cloud {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "quantum-security-posture"
  #   }
  # }

  # Alternative: Local backend (default, not recommended for production)
  # backend "local" {
  #   path = "terraform.tfstate"
  # }
}

# ============================================================================
# Provider Configuration
# ============================================================================

# Default Google Cloud provider configuration
provider "google" {
  # Project and region will be set via variables
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable request/response logging for debugging (disable in production)
  request_timeout = "60s"

  # Default labels to apply to all resources
  default_labels = var.resource_labels

  # Batching configuration for improved performance
  batching {
    send_after      = "10s"
    enable_batching = true
  }
}

# Google Cloud Beta provider for preview features like post-quantum cryptography
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels to apply to all beta resources
  default_labels = var.resource_labels

  # Batching configuration
  batching {
    send_after      = "10s"
    enable_batching = true
  }
}

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

# Null provider configuration
provider "null" {
  # No specific configuration required
}

# ============================================================================
# Terraform Configuration
# ============================================================================

# Configure Terraform CLI behavior
terraform {
  # Experimental features (use with caution)
  experiments = []

  # Provider installation configuration
  provider_meta "google" {
    module_name = "quantum-safe-security-posture-management"
  }

  provider_meta "google-beta" {
    module_name = "quantum-safe-security-posture-management"
  }
}

# ============================================================================
# Version Compatibility Notes
# ============================================================================

# Terraform >= 1.5.0 required for:
# - Enhanced state management features
# - Improved provider plugin caching
# - Better error handling and diagnostics
# - Support for complex variable validation

# Google Provider >= 5.0 required for:
# - Post-quantum cryptography support in Cloud KMS
# - Enhanced Security Command Center integration
# - Improved Cloud Asset Inventory features
# - Latest organization policy constraints
# - Advanced Cloud Functions configuration options

# Google-Beta Provider >= 5.0 required for:
# - Preview post-quantum cryptography algorithms
# - Beta Security Command Center features
# - Advanced monitoring and alerting capabilities
# - Preview organization policy features

# Archive Provider >= 2.4 required for:
# - Improved ZIP file creation performance
# - Better handling of large source files
# - Enhanced compression options

# Random Provider >= 3.5 required for:
# - Improved random string generation
# - Better entropy sources
# - Enhanced security for random values

# Time Provider >= 0.9 required for:
# - Accurate time-based resource management
# - Better timezone handling
# - Improved time formatting options

# Null Provider >= 3.2 required for:
# - Enhanced local-exec provisioner
# - Better error handling for external commands
# - Improved resource lifecycle management

# ============================================================================
# Provider Feature Requirements
# ============================================================================

# The following Google Cloud APIs must be enabled in the target project:
# - Cloud Key Management Service API (cloudkms.googleapis.com)
# - Security Command Center API (securitycenter.googleapis.com)
# - Cloud Asset Inventory API (cloudasset.googleapis.com)
# - Cloud Monitoring API (monitoring.googleapis.com)
# - Cloud Logging API (logging.googleapis.com)
# - Cloud Resource Manager API (cloudresourcemanager.googleapis.com)
# - Pub/Sub API (pubsub.googleapis.com)
# - Cloud Storage API (storage.googleapis.com)
# - Cloud Functions API (cloudfunctions.googleapis.com)
# - Cloud Scheduler API (cloudscheduler.googleapis.com)
# - Cloud Build API (cloudbuild.googleapis.com)
# - Organization Policy API (orgpolicy.googleapis.com)

# Required IAM permissions for the Terraform service account:
# - Organization Policy Administrator (roles/orgpolicy.policyAdmin)
# - Security Center Admin (roles/securitycenter.admin)
# - Cloud KMS Admin (roles/cloudkms.admin)
# - Cloud Asset Viewer (roles/cloudasset.viewer)
# - Monitoring Editor (roles/monitoring.editor)
# - Logging Admin (roles/logging.admin)
# - Pub/Sub Editor (roles/pubsub.editor)
# - Storage Admin (roles/storage.admin)
# - Cloud Functions Developer (roles/cloudfunctions.developer)
# - Cloud Scheduler Admin (roles/cloudscheduler.admin)
# - Service Account Admin (roles/iam.serviceAccountAdmin)
# - Project IAM Admin (roles/resourcemanager.projectIamAdmin)

# ============================================================================
# Upgrade Path and Compatibility
# ============================================================================

# When upgrading provider versions:
# 1. Review the provider changelog for breaking changes
# 2. Test in a non-production environment first
# 3. Update this file with new version constraints
# 4. Run 'terraform init -upgrade' to update providers
# 5. Run 'terraform plan' to review proposed changes
# 6. Apply changes incrementally in production

# Google Provider Upgrade Notes:
# - Major version upgrades may require resource recreation
# - Monitor for deprecated resource arguments
# - Review new security defaults and requirements
# - Test post-quantum cryptography compatibility

# Terraform Version Upgrade Notes:
# - Review state file format compatibility
# - Check for deprecated language features
# - Update CI/CD pipelines with new Terraform version
# - Validate all modules and configurations

# ============================================================================
# Development and Testing Configuration
# ============================================================================

# For development environments, you may want to use specific provider versions
# to ensure consistent behavior across team members:

# provider "google" {
#   version = "= 5.x.x"  # Pin to specific version for consistency
# }

# For production environments, use constraint-based versioning to allow
# patch updates while preventing breaking changes:

# provider "google" {
#   version = "~> 5.0"  # Allow 5.x.x but not 6.x.x
# }

# ============================================================================
# Regional Availability Notes
# ============================================================================

# Post-quantum cryptography features may have limited regional availability:
# - Ensure selected region supports KMS post-quantum algorithms
# - Verify Security Command Center Enterprise availability
# - Check Cloud Asset Inventory organization-level features
# - Confirm Cloud Functions regional deployment options

# Current regions with full post-quantum cryptography support:
# - us-central1 (Iowa) - Recommended for North America
# - us-east1 (South Carolina)
# - europe-west1 (Belgium) - Recommended for Europe
# - asia-east1 (Taiwan) - Recommended for Asia Pacific

# ============================================================================
# Cost Optimization Notes
# ============================================================================

# Provider configuration options that can impact costs:
# - Enable batching to reduce API calls
# - Use appropriate request timeouts
# - Configure proper lifecycle rules for storage
# - Optimize monitoring metric retention periods
# - Use cost-effective storage classes for archival data

# Regular cost monitoring recommended:
# - Review Google Cloud billing dashboards
# - Monitor resource usage metrics
# - Optimize based on actual usage patterns
# - Consider reserved capacity for predictable workloads