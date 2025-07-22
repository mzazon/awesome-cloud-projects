# Terraform version and provider requirements
# This configuration ensures compatibility with Google Cloud provider features

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Google Cloud provider with project and region
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Cloud Beta provider for features in beta
provider "google-beta" {
  project = var.project_id
  region  = var.region
}