# Terraform and provider version requirements for GCP content performance optimization
# This configuration ensures compatibility with Google Cloud APIs and Terraform features

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    
    # Google Cloud Platform Beta provider for preview features (if needed)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Archive provider for packaging Cloud Function source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
  }
}

# Configure the Google Cloud Provider with default project and region
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