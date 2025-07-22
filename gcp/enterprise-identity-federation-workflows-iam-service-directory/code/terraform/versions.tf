# ==============================================================================
# TERRAFORM AND PROVIDER VERSION REQUIREMENTS
# Enterprise Identity Federation Workflows with Cloud IAM and Service Directory
# ==============================================================================

terraform {
  # Specify the minimum Terraform version required
  required_version = ">= 1.5.0"
  
  # Configure required providers with version constraints
  required_providers {
    # Google Cloud Platform provider (main)
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    
    # Google Cloud Platform provider (beta features)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Archive provider for creating zip files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Time provider for managing time-based resources
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
  
  # Optional: Configure remote state backend
  # Uncomment and modify the following block to use Google Cloud Storage for state storage
  # backend "gcs" {
  #   bucket  = "your-terraform-state-bucket"
  #   prefix  = "enterprise-identity-federation"
  # }
}

# ==============================================================================
# GOOGLE CLOUD PROVIDER CONFIGURATION
# ==============================================================================

# Primary Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Default labels to apply to all resources (if supported by the resource)
  default_labels = {
    managed_by   = "terraform"
    environment  = var.environment
    component    = "enterprise-identity-federation"
    terraform    = "true"
  }
  
  # Batching configuration for improved performance
  batching {
    send_after      = "10s"
    enable_batching = true
  }
  
  # Request timeout configuration
  request_timeout = "60s"
}

# Google Cloud Beta provider for accessing beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Default labels to apply to all resources (if supported by the resource)
  default_labels = {
    managed_by   = "terraform"
    environment  = var.environment
    component    = "enterprise-identity-federation"
    terraform    = "true"
    provider     = "beta"
  }
  
  # Batching configuration for improved performance
  batching {
    send_after      = "10s"
    enable_batching = true
  }
  
  # Request timeout configuration
  request_timeout = "60s"
}

# ==============================================================================
# PROVIDER FEATURE FLAGS AND CONFIGURATION
# ==============================================================================

# Enable specific Google Cloud provider features
# These configurations optimize provider behavior for enterprise use cases

# Configure the Google provider to handle large-scale deployments
locals {
  # Provider configuration flags
  enable_resource_manager_v3 = true
  enable_iam_beta_features  = true
  enable_compute_beta_apis  = false # Set to true if using compute beta features
  
  # Retry configuration for API calls
  max_retries = 3
  retry_delay = "5s"
}

# ==============================================================================
# DATA SOURCES FOR PROVIDER VALIDATION
# ==============================================================================

# Validate that the required APIs are available in the project
data "google_project" "current" {
  project_id = var.project_id
}

# Get current project number for IAM configurations
data "google_project" "project_info" {
  project_id = var.project_id
}

# Validate region and zone configuration
data "google_compute_zones" "available" {
  region  = var.region
  project = var.project_id
}

# ==============================================================================
# TERRAFORM CONFIGURATION VALIDATION
# ==============================================================================

# Validate that the project exists and is accessible
resource "null_resource" "validate_project" {
  triggers = {
    project_id     = var.project_id
    project_number = data.google_project.project_info.number
  }
  
  lifecycle {
    precondition {
      condition     = data.google_project.current.project_id == var.project_id
      error_message = "Project ${var.project_id} is not accessible or does not exist."
    }
    
    precondition {
      condition     = length(data.google_compute_zones.available.names) > 0
      error_message = "No compute zones available in region ${var.region}."
    }
  }
}

# ==============================================================================
# PROVIDER COMPATIBILITY AND FEATURE MATRIX
# ==============================================================================

# This configuration is compatible with the following provider versions:
#
# google         >= 5.0, < 7.0 (recommended: ~> 6.0)
# google-beta    >= 5.0, < 7.0 (recommended: ~> 6.0)
# random         >= 3.4, < 4.0 (recommended: ~> 3.6)
# archive        >= 2.2, < 3.0 (recommended: ~> 2.4)
# time           >= 0.9, < 1.0 (recommended: ~> 0.12)
#
# Features used that require specific provider versions:
# - Workload Identity Federation: google >= 4.47.0
# - Service Directory (beta): google-beta >= 4.0.0
# - Cloud Functions 2nd gen: google >= 4.44.0
# - Secret Manager: google >= 3.45.0
# - DNS managed zones: google >= 3.0.0
# - Project service management: google >= 3.0.0
#
# Beta features in use:
# - Service Directory namespace and services
# - Advanced Workload Identity Pool configurations
#
# ==============================================================================
# STATE MANAGEMENT RECOMMENDATIONS
# ==============================================================================

# For production deployments, consider using remote state storage:
#
# 1. Google Cloud Storage backend:
#    - Provides versioning and encryption
#    - Supports state locking with Cloud Storage
#    - Integrates with IAM for access control
#
# 2. Terraform Cloud:
#    - Managed state storage and execution
#    - Built-in access controls and audit logging
#    - Integration with VCS for plan/apply workflows
#
# 3. HashiCorp Consul:
#    - Distributed state storage
#    - Strong consistency and locking
#    - Suitable for multi-region deployments
#
# Example GCS backend configuration:
# terraform {
#   backend "gcs" {
#     bucket                      = "your-terraform-state-bucket"
#     prefix                      = "enterprise-identity-federation"
#     impersonate_service_account = "terraform-state@your-project.iam.gserviceaccount.com"
#   }
# }

# ==============================================================================
# UPGRADE GUIDANCE
# ==============================================================================

# When upgrading providers:
#
# 1. Review the provider changelog for breaking changes
# 2. Test in a non-production environment first
# 3. Use `terraform plan` to preview changes
# 4. Consider using provider version constraints to control upgrades
# 5. Update the required_providers block incrementally
#
# Common upgrade paths:
# - google 5.x -> 6.x: Review IAM and resource naming changes
# - terraform 1.4 -> 1.5+: Leverage new import block syntax
# - google-beta features: Monitor for promotion to stable API

# ==============================================================================
# DEBUGGING AND TROUBLESHOOTING
# ==============================================================================

# Environment variables for debugging:
# - TF_LOG=DEBUG for detailed Terraform logs
# - TF_LOG_PROVIDER=DEBUG for provider-specific logs
# - GOOGLE_OAUTH_ACCESS_TOKEN for authentication debugging
# - GOOGLE_CLOUD_QUOTA_PROJECT for quota project override
#
# Common authentication methods:
# 1. Application Default Credentials (ADC)
# 2. Service Account Key Files
# 3. Google Cloud SDK authentication
# 4. Workload Identity Federation (for CI/CD)
#
# Validation commands:
# - gcloud auth list
# - gcloud config list
# - gcloud projects list
# - terraform providers schema