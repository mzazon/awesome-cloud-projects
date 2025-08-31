# Terraform and Provider Version Constraints
# This file defines the minimum versions required for Terraform and providers

terraform {
  required_version = ">= 1.5"

  required_providers {
    # Google Cloud Provider for infrastructure resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.12"
    }

    # Google Beta Provider for advanced/preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.12"
    }

    # Archive Provider for creating deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random Provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Google Cloud Provider
# Default settings for all Google Cloud resources
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Beta Provider
# Used for preview features and advanced configurations
provider "google-beta" {
  project = var.project_id
  region  = var.region
}