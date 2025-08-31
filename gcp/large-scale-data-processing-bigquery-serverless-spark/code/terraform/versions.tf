# ==============================================================================
# TERRAFORM PROVIDER VERSIONS AND REQUIREMENTS
# ==============================================================================
# This file defines the Terraform version requirements and provider
# configurations for the BigQuery Serverless Spark data processing
# infrastructure. It ensures consistent provider versions and enables
# required features across all team members and environments.
# ==============================================================================

terraform {
  # Terraform version requirements
  required_version = ">= 1.5.0"

  # Provider requirements with version constraints
  required_providers {
    # Google Cloud Provider
    google = {
      source  = "hashicorp/google"
      version = "~> 5.12"
    }

    # Google Beta Provider (for preview features)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.12"
    }

    # Random Provider (for generating unique resource names)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Local Provider (for local file operations and data processing)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Template Provider (for file templating)
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }

    # Null Provider (for running local commands and provisioners)
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    # Time Provider (for time-based resources and delays)
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }

  # Backend configuration for state storage
  # Uncomment and configure for production use
  # backend "gcs" {
  #   bucket  = "your-terraform-state-bucket"
  #   prefix  = "bigquery-serverless-spark"
  # }

  # Experimental features (if needed)
  # experiments = [module_variable_optional_attrs]
}

# ==============================================================================
# GOOGLE CLOUD PROVIDER CONFIGURATION
# ==============================================================================
# Configure the Google Cloud Provider with default settings
# Project and region can be overridden by variables

provider "google" {
  project = var.project_id
  region  = var.region

  # Default labels to apply to all resources
  default_labels = {
    terraform   = "true"
    environment = var.environment
    project     = "bigquery-serverless-spark"
    managed-by  = "terraform"
  }

  # Enable batching for better performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }

  # Request timeout settings
  request_timeout = "60s"

  # User agent information
  user_project_override = true
  billing_project       = var.project_id
}

# ==============================================================================
# GOOGLE BETA PROVIDER CONFIGURATION
# ==============================================================================
# Configure the Google Beta Provider for preview features
# Used for latest BigQuery and Dataproc features

provider "google-beta" {
  project = var.project_id
  region  = var.region

  # Default labels to apply to all resources
  default_labels = {
    terraform   = "true"
    environment = var.environment
    project     = "bigquery-serverless-spark"
    managed-by  = "terraform"
  }

  # Enable batching for better performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }

  # Request timeout settings
  request_timeout = "60s"

  # User agent information
  user_project_override = true
  billing_project       = var.project_id
}

# ==============================================================================
# RANDOM PROVIDER CONFIGURATION
# ==============================================================================
# Configure the Random Provider for generating unique identifiers

provider "random" {
  # No specific configuration needed
}

# ==============================================================================
# LOCAL PROVIDER CONFIGURATION
# ==============================================================================
# Configure the Local Provider for local file operations

provider "local" {
  # No specific configuration needed
}

# ==============================================================================
# TEMPLATE PROVIDER CONFIGURATION
# ==============================================================================
# Configure the Template Provider for file templating

provider "template" {
  # No specific configuration needed
}

# ==============================================================================
# NULL PROVIDER CONFIGURATION
# ==============================================================================
# Configure the Null Provider for local command execution

provider "null" {
  # No specific configuration needed
}

# ==============================================================================
# TIME PROVIDER CONFIGURATION
# ==============================================================================
# Configure the Time Provider for time-based resources

provider "time" {
  # No specific configuration needed
}

# ==============================================================================
# TERRAFORM CLOUD/ENTERPRISE CONFIGURATION
# ==============================================================================
# Uncomment and configure for Terraform Cloud or Enterprise

# terraform {
#   cloud {
#     organization = "your-organization"
#     
#     workspaces {
#       name = "bigquery-serverless-spark-${var.environment}"
#     }
#   }
# }

# ==============================================================================
# PROVIDER FEATURE FLAGS
# ==============================================================================
# Configure provider feature flags for consistent behavior

# Google Provider features
locals {
  google_provider_features = {
    # Enable new resource behavior
    enable_resource_manager_v1 = false
    enable_compute_alpha       = false
    enable_bigquery_v2         = true
    enable_dataproc_v1         = true
    
    # Enable experimental features
    enable_experimental_features = var.environment == "development"
  }
}

# ==============================================================================
# VERSION COMPATIBILITY MATRIX
# ==============================================================================
# The following versions have been tested together:
#
# Terraform Core: >= 1.5.0, < 2.0.0
# Google Provider: >= 5.12.0, < 6.0.0
# Google Beta Provider: >= 5.12.0, < 6.0.0
# Random Provider: >= 3.6.0, < 4.0.0
# Local Provider: >= 2.4.0, < 3.0.0
# Template Provider: >= 2.2.0, < 3.0.0
# Null Provider: >= 3.2.0, < 4.0.0
# Time Provider: >= 0.11.0, < 1.0.0
#
# For production environments, consider pinning to exact versions:
# version = "= 5.12.0" instead of "~> 5.12"

# ==============================================================================
# PROVIDER ALIASES
# ==============================================================================
# Define provider aliases for multi-region or multi-project deployments

# Alternative region provider (if needed for multi-region setup)
provider "google" {
  alias   = "secondary_region"
  project = var.project_id
  region  = "us-east1"  # Different region for disaster recovery

  default_labels = {
    terraform   = "true"
    environment = var.environment
    project     = "bigquery-serverless-spark"
    managed-by  = "terraform"
    region-type = "secondary"
  }
}

# Alternative project provider (if needed for cross-project setup)
# provider "google" {
#   alias   = "shared_services"
#   project = "shared-services-project-id"
#   region  = var.region
#
#   default_labels = {
#     terraform   = "true"
#     environment = var.environment
#     project     = "bigquery-serverless-spark"
#     managed-by  = "terraform"
#     project-type = "shared-services"
#   }
# }

# ==============================================================================
# TERRAFORM SETTINGS FOR CI/CD
# ==============================================================================
# Additional settings for CI/CD pipeline compatibility

# Disable interactive input for automated deployments
# terraform {
#   cli = false
# }