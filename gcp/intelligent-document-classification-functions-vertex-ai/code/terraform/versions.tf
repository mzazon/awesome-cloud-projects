# Terraform and provider version requirements for GCP document classification solution
# This configuration ensures compatibility and reproducible deployments

terraform {
  required_version = ">= 1.8"
  
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

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}