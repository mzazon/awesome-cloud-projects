# Terraform Provider Requirements for Visual Document Processing Solution
# This file defines the minimum required versions and provider configurations

terraform {
  # Require minimum Terraform version that supports all features used
  required_version = ">= 1.5.0"

  required_providers {
    # Google Cloud Platform Provider
    google = {
      source  = "hashicorp/google"
      version = "~> 5.12.0"
    }

    # Google Cloud Platform Beta Provider for advanced features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.12.0"
    }

    # Random provider for generating unique resource names and IDs
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }

    # Archive provider for creating function source archives
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable request batching for better performance
  batching {
    enable_batching = true
  }

  # Default labels applied to all resources
  default_labels = {
    environment   = var.environment
    solution      = "visual-document-processing"
    managed-by    = "terraform"
    recipe-id     = "8a9b4c3d"
  }
}

# Configure the Google Cloud Beta Provider for advanced features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable request batching for better performance
  batching {
    enable_batching = true
  }

  # Default labels applied to all resources
  default_labels = {
    environment   = var.environment
    solution      = "visual-document-processing"
    managed-by    = "terraform"
    recipe-id     = "8a9b4c3d"
  }
}

# Configure the Random Provider
provider "random" {}

# Configure the Archive Provider
provider "archive" {}