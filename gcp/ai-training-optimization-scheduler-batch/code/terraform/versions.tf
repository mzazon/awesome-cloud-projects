# Terraform version and provider requirements for AI Training Optimization
# This configuration specifies the minimum versions required for reliable deployment

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Google Cloud Provider for primary infrastructure resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Beta Provider for preview features and advanced configurations
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Local provider for file operations and data processing
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all resources for cost tracking and management
  default_labels = {
    terraform   = "true"
    environment = var.environment
    workload    = "ai-training"
    recipe      = "ai-training-optimization-scheduler-batch"
  }
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Consistent labeling across all providers
  default_labels = {
    terraform   = "true"
    environment = var.environment
    workload    = "ai-training"
    recipe      = "ai-training-optimization-scheduler-batch"
  }
}