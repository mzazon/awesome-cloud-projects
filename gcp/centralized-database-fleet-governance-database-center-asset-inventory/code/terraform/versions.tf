# Terraform and Provider Version Constraints
# Centralized Database Fleet Governance with Database Center and Cloud Asset Inventory

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.10.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.10.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

# Default Google Cloud Provider Configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

# Google Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}