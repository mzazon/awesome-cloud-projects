# Terraform version and provider requirements
# This file specifies the minimum versions and required providers for the email signature generator solution

terraform {
  # Require minimum Terraform version for latest features and stability
  required_version = ">= 1.5"

  # Define required providers with version constraints
  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Archive provider for creating ZIP files from source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the Google Cloud provider with project and region defaults
provider "google" {
  # Project ID will be provided via variables or environment
  project = var.project_id
  region  = var.region
}