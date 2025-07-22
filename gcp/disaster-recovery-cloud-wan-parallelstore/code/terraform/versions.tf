# Terraform provider version constraints for GCP disaster recovery solution
# This configuration ensures compatibility with the latest GCP provider features
# while maintaining stability for production deployments

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
  }
}

# Primary provider configuration for main region deployment
provider "google" {
  project = var.project_id
  region  = var.primary_region
  zone    = var.primary_zone
}

# Beta provider for accessing preview features like Parallelstore
provider "google-beta" {
  project = var.project_id
  region  = var.primary_region
  zone    = var.primary_zone
}

# Secondary provider for disaster recovery region
provider "google" {
  alias   = "secondary"
  project = var.project_id
  region  = var.secondary_region
  zone    = var.secondary_zone
}

# Beta provider for secondary region
provider "google-beta" {
  alias   = "secondary"
  project = var.project_id
  region  = var.secondary_region
  zone    = var.secondary_zone
}