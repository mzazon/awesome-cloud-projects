# Terraform and Provider Version Constraints
# Smart Form Processing with Document AI and Gemini
# This file defines the required versions for Terraform and all providers used in this configuration

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Platform Beta provider for newer/beta features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Archive provider for creating ZIP files for Cloud Function deployment
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider for beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}