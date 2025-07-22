# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers
# to ensure compatibility and access to the latest features

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.6.0"

  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44.0"
    }

    # Google Cloud Platform Beta provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }

    # Archive provider for creating ZIP files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }

    # Null provider for triggers and local execution
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }

    # Template provider for generating configuration files
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2.0"
    }
  }

  # Optional: Configure backend for state management
  # Uncomment and configure for production deployments
  /*
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "translation-pipeline"
  }
  */
}

# Default Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region

  # Default labels applied to all resources
  default_labels = {
    managed_by  = "terraform"
    environment = var.environment
    component   = "translation-pipeline"
  }

  # User project override for quota and billing
  user_project_override = true

  # Request timeout for API calls
  request_timeout = "60s"
}

# Google Cloud Beta provider for accessing preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region

  # Default labels for beta resources
  default_labels = {
    managed_by  = "terraform"
    environment = var.environment
    component   = "translation-pipeline"
    beta_feature = "true"
  }

  user_project_override = true
  request_timeout = "60s"
}

# Random provider configuration
provider "random" {
  # No specific configuration required
}

# Archive provider configuration
provider "archive" {
  # No specific configuration required
}

# Null provider configuration
provider "null" {
  # No specific configuration required
}

# Template provider configuration (deprecated but still used for compatibility)
provider "template" {
  # No specific configuration required
}