# ============================================================================
# Smart Email Template Generation with Gemini and Firestore - Provider Versions
# ============================================================================
# This file defines the Terraform and provider version requirements for
# the AI-powered email template generator infrastructure deployment.
# It ensures compatibility and stability across different environments.
# ============================================================================

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.5.0"

  # Required providers with version constraints
  required_providers {
    # Google Cloud Provider - Primary provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Beta Provider - For accessing beta features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Random Provider - For generating unique resource names and identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Archive Provider - For creating ZIP archives of function source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Local Provider - For local file operations and data processing
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }

    # Template Provider - For rendering configuration templates
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }

  # Optional: Configure backend for state management
  # Uncomment and configure the backend block below for production deployments
  
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "terraform/email-template-generator"
  # }
}

# ============================================================================
# PROVIDER CONFIGURATIONS
# ============================================================================

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region

  # Set default labels for all resources
  default_labels = {
    environment = var.environment
    application = "email-template-generator"
    managed-by  = "terraform"
    recipe-id   = "f4a7b2c9"
  }

  # Enable request logging for debugging (disable in production)
  request_timeout = "120s"

  # Configure user project override for quota and billing
  user_project_override = true

  # Configure batching for API requests to improve performance
  batching {
    send_after      = "5s"
    enable_batching = true
  }
}

# Configure the Google Cloud Beta Provider for beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region

  # Set default labels for all resources
  default_labels = {
    environment = var.environment
    application = "email-template-generator"
    managed-by  = "terraform"
    recipe-id   = "f4a7b2c9"
  }

  # Configure request timeout
  request_timeout = "120s"

  # Configure user project override
  user_project_override = true

  # Configure batching for API requests
  batching {
    send_after      = "5s"
    enable_batching = true
  }
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required for random provider
}

# Configure the Archive Provider
provider "archive" {
  # No specific configuration required for archive provider
}

# Configure the Local Provider
provider "local" {
  # No specific configuration required for local provider
}

# ============================================================================
# TERRAFORM CONFIGURATION
# ============================================================================

# Configure Terraform behavior
terraform {
  # Configure experiment features (use with caution)
  experiments = []

  # Cloud configuration for Terraform Cloud/Enterprise (optional)
  # cloud {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "email-template-generator"
  #   }
  # }
}

# ============================================================================
# VERSION COMPATIBILITY NOTES
# ============================================================================

# Provider Version Compatibility:
# - google ~> 6.0: Latest stable version with full feature support
# - google-beta ~> 6.0: Beta features for Cloud Functions Gen2 and Firestore
# - random ~> 3.6: Stable version for resource naming
# - archive ~> 2.4: Latest version for ZIP file creation
# - local ~> 2.5: Latest version for local file operations
# - template ~> 2.2: Latest version for template rendering

# Terraform Version Requirements:
# - >= 1.5.0: Required for modern provider features and syntax
# - Recommended: Use Terraform >= 1.6.0 for best performance

# Google Cloud API Requirements:
# The following APIs must be enabled in your project:
# - Cloud Functions API (cloudfunctions.googleapis.com)
# - Firestore API (firestore.googleapis.com)
# - Vertex AI API (aiplatform.googleapis.com)
# - Cloud Build API (cloudbuild.googleapis.com)
# - Cloud Resource Manager API (cloudresourcemanager.googleapis.com)
# - Service Usage API (serviceusage.googleapis.com)

# ============================================================================
# UPGRADE NOTES
# ============================================================================

# When upgrading provider versions:
# 1. Review the provider changelog for breaking changes
# 2. Test in a development environment first
# 3. Update the version constraints gradually
# 4. Run 'terraform plan' to review changes before applying
# 5. Keep provider versions consistent across team members

# When upgrading Terraform versions:
# 1. Check compatibility with required providers
# 2. Review Terraform changelog for syntax changes
# 3. Update CI/CD pipelines to use the new version
# 4. Consider using .terraform-version file for version pinning

# ============================================================================
# FEATURE FLAGS AND EXPERIMENTS
# ============================================================================

# Terraform experiment features that may be enabled:
# - module_variable_optional_attrs: For optional variable attributes
# - config_driven_move: For configuration-driven resource moves

# Note: Experiments should be used cautiously and removed when features
# become stable. They may be removed in future Terraform versions.

# ============================================================================
# STATE MANAGEMENT RECOMMENDATIONS
# ============================================================================

# For production deployments, consider:
# 1. Remote state storage (Google Cloud Storage recommended for GCP)
# 2. State locking to prevent concurrent modifications
# 3. State encryption for sensitive data protection
# 4. State versioning for rollback capabilities
# 5. Separate state files for different environments

# Example GCS backend configuration:
# backend "gcs" {
#   bucket                      = "your-terraform-state-bucket"
#   prefix                      = "terraform/email-template-generator"
#   impersonate_service_account = "terraform@your-project.iam.gserviceaccount.com"
# }

# ============================================================================
# PROVIDER AUTHENTICATION
# ============================================================================

# Authentication methods for Google Cloud Provider:
# 1. Application Default Credentials (ADC) - Recommended for local development
# 2. Service Account Key File - For CI/CD and automation
# 3. Workload Identity - For running in GKE or Cloud Run
# 4. gcloud auth application-default login - For local development

# For production environments, use service accounts with minimal required permissions:
# - roles/cloudfunctions.admin (for function management)
# - roles/firestore.databaseAdmin (for database management)
# - roles/aiplatform.user (for Vertex AI access)
# - roles/storage.admin (for Cloud Storage bucket management)
# - roles/iam.serviceAccountAdmin (for service account management)
# - roles/monitoring.metricWriter (for monitoring and logging)