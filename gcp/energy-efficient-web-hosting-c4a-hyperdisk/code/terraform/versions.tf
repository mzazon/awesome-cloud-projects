# Terraform version and provider requirements for Energy-Efficient Web Hosting with C4A and Hyperdisk
# This configuration specifies the minimum Terraform version and required providers
# for deploying ARM-based C4A instances with Hyperdisk storage and load balancing

terraform {
  required_version = ">= 1.6"

  required_providers {
    # Google Cloud Provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Beta Provider for accessing preview features and advanced configurations
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Google Cloud Provider with project and region settings
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}