# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.5"

  required_providers {
    # Google Cloud Provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Beta Provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Local provider for local file operations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}