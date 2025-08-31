# ============================================================================
# API Schema Generation with Gemini Code Assist and Cloud Build - Provider Versions
# ============================================================================
# This file defines the required Terraform version and provider configurations
# with version constraints to ensure compatibility and reproducible deployments.

# ============================================================================
# Terraform Version Requirements
# ============================================================================

terraform {
  # Require Terraform version 1.0 or higher for optimal stability and features
  required_version = ">= 1.0"

  # Required providers with version constraints
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

    # Random provider for generating unique identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Archive provider for creating ZIP files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Local provider for creating local files and directories
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Time provider for time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }

  # Optional: Configure Terraform Cloud or Terraform Enterprise backend
  # Uncomment and modify the following block if using remote state storage
  
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "api-schema-generation/terraform.tfstate"
  # }

  # backend "remote" {
  #   organization = "your-terraform-cloud-org"
  #   workspaces {
  #     name = "api-schema-generation-workspace"
  #   }
  # }
}

# ============================================================================
# Google Cloud Provider Configuration
# ============================================================================

# Primary Google Cloud provider configuration
provider "google" {
  # Project and region will be specified via variables
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all resources
  default_labels = merge(
    {
      environment    = var.environment
      managed-by     = "terraform"
      component      = "api-schema-generation"
      deployment     = "automated"
      terraform-workspace = terraform.workspace
    },
    var.additional_labels
  )

  # Batching configuration for improved performance
  batching {
    enable_batching = true
    send_after      = "30s"
  }

  # Request timeout for API calls
  request_timeout = "60s"

  # User project override for billing
  user_project_override = true

  # Add custom user agent for tracking
  add_terraform_attribution_label = true
}

# Google Cloud Beta provider for accessing preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all beta resources
  default_labels = merge(
    {
      environment    = var.environment
      managed-by     = "terraform"
      component      = "api-schema-generation"
      deployment     = "automated"
      terraform-workspace = terraform.workspace
      provider-type  = "beta"
    },
    var.additional_labels
  )

  # Batching configuration for improved performance
  batching {
    enable_batching = true
    send_after      = "30s"
  }

  # Request timeout for API calls
  request_timeout = "60s"

  # User project override for billing
  user_project_override = true

  # Add custom user agent for tracking
  add_terraform_attribution_label = true
}

# ============================================================================
# Provider Feature Configuration
# ============================================================================

# Random provider configuration
provider "random" {
  # No specific configuration needed for random provider
}

# Archive provider configuration  
provider "archive" {
  # No specific configuration needed for archive provider
}

# Local provider configuration
provider "local" {
  # No specific configuration needed for local provider
}

# Time provider configuration
provider "time" {
  # No specific configuration needed for time provider
}

# ============================================================================
# Provider Version Information
# ============================================================================

# Data source to retrieve provider version information
data "google_client_config" "current" {}

# Local values for provider version tracking
locals {
  # Provider version information for outputs and debugging
  provider_versions = {
    terraform_version = "~> 1.0"
    google_provider = {
      version = "~> 5.0"
      source  = "hashicorp/google"
    }
    google_beta_provider = {
      version = "~> 5.0"
      source  = "hashicorp/google-beta"
    }
    random_provider = {
      version = "~> 3.6"
      source  = "hashicorp/random"
    }
    archive_provider = {
      version = "~> 2.4"
      source  = "hashicorp/archive"
    }
    local_provider = {
      version = "~> 2.4"
      source  = "hashicorp/local"
    }
    time_provider = {
      version = "~> 0.11"
      source  = "hashicorp/time"
    }
  }

  # Provider compatibility information
  compatibility_info = {
    terraform_minimum = "1.0.0"
    google_provider_minimum = "5.0.0"
    last_tested_versions = {
      terraform = "1.6.6"
      google = "5.11.0"
      google_beta = "5.11.0"
    }
  }

  # Feature flags based on provider versions
  provider_features = {
    # Enable advanced features based on provider version
    enable_uniform_bucket_level_access = true
    enable_retention_policy = true
    enable_lifecycle_rules = true
    enable_versioning = true
    enable_labels = true
    enable_iam_conditions = true
    enable_monitoring_v2 = true
    enable_cloud_functions_v2 = false # Use v1 for broader compatibility
  }
}

# ============================================================================
# Provider Configuration Validation
# ============================================================================

# Validation to ensure required providers are available
check "provider_versions" {
  assert {
    condition = can(regex("^5\\.", data.google_client_config.current.project))
    error_message = "Google Cloud provider version must be 5.x or higher for compatibility."
  }
}

# ============================================================================
# Deprecated Provider Features
# ============================================================================

# Note: The following provider features are deprecated and should be avoided:
# - google_project_services (use google_project_service instead)
# - Legacy IAM bindings (use google_project_iam_* resources)
# - Old-style bucket IAM (use uniform bucket-level access)
# - Legacy monitoring (use Monitoring API v2)

# ============================================================================
# Provider Migration Notes
# ============================================================================

# Migration notes for major version upgrades:
#
# From Google Provider 4.x to 5.x:
# - Review IAM policy changes and member formatting
# - Update deprecated resource arguments
# - Verify Cloud Function runtime compatibility
# - Check storage bucket uniform access settings
#
# From Terraform 0.15.x to 1.x:
# - Update required_version constraint
# - Review provider version constraints
# - Validate configuration syntax changes
# - Update any deprecated configuration blocks

# ============================================================================
# Provider Security Configuration
# ============================================================================

# Security considerations for provider configuration:
#
# 1. Authentication:
#    - Use service account key files or workload identity
#    - Avoid hardcoding credentials in configuration
#    - Use environment variables for sensitive data
#
# 2. Authorization:
#    - Follow principle of least privilege
#    - Use IAM conditions where applicable
#    - Regularly audit provider permissions
#
# 3. Network Security:
#    - Consider VPC Service Controls
#    - Use private Google access when possible
#    - Implement network security policies
#
# 4. Data Protection:
#    - Enable encryption at rest and in transit
#    - Use Cloud KMS for key management
#    - Implement appropriate retention policies

# ============================================================================
# Provider Performance Optimization
# ============================================================================

# Performance optimization settings:
#
# 1. Batching:
#    - Enabled batching for improved API performance
#    - Configured appropriate send_after timing
#
# 2. Timeouts:
#    - Set reasonable request timeouts
#    - Consider network latency in timeout values
#
# 3. Parallelism:
#    - Use terraform apply -parallelism=N for large deployments
#    - Consider resource dependencies for parallel execution
#
# 4. State Management:
#    - Use remote state for team collaboration
#    - Enable state locking for consistency
#    - Regular state file cleanup and optimization

# ============================================================================
# Provider Debugging and Troubleshooting
# ============================================================================

# Debugging environment variables (for troubleshooting):
# export TF_LOG=DEBUG                    # Enable debug logging
# export TF_LOG_PROVIDER=DEBUG          # Provider-specific debug logging
# export GOOGLE_CREDENTIALS=path/to/key # Service account key path
# export GOOGLE_APPLICATION_CREDENTIALS=path/to/key # Application default credentials
# export TF_LOG_PATH=terraform.log      # Log to file

# Common troubleshooting commands:
# terraform providers                   # List providers and versions
# terraform providers schema            # Show provider schemas
# terraform refresh                     # Refresh state from real infrastructure
# terraform plan -detailed-exitcode    # Plan with detailed exit codes
# terraform apply -auto-approve         # Apply without confirmation (use with caution)