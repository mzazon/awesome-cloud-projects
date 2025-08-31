# Terraform version and provider requirements
# This file defines the minimum Terraform version and provider versions required for this configuration

terraform {
  # Require Terraform version 1.0 or higher for optimal performance and features
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # Google Cloud Provider - official provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Archive provider for creating ZIP files of function source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Default provider configuration for Google Cloud
# Additional configuration can be provided via environment variables or provider blocks
provider "google" {
  # Project and region can be set via variables or environment variables:
  # export GOOGLE_PROJECT=your-project-id
  # export GOOGLE_REGION=us-central1
  project = var.project_id
  region  = var.region
}

# Archive provider - no additional configuration needed
provider "archive" {}

# Random provider - no additional configuration needed  
provider "random" {}