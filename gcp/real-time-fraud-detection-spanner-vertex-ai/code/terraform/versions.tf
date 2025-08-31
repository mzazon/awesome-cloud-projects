# Terraform and provider version constraints for GCP fraud detection system
# This configuration ensures compatibility and stability across deployments

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.10.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.10.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10.0"
    }
  }
}

# Default provider configuration for Google Cloud
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Beta provider for accessing preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}