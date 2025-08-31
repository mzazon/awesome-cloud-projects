# Terraform and provider version requirements
# This file defines the minimum Terraform version and required providers
# for the sustainability compliance automation solution

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Beta provider for resources requiring beta features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Archive provider for creating function source archives
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Cloud Beta Provider for beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}