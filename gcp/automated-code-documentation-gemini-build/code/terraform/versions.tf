# Terraform version and provider requirements for automated code documentation solution
# This configuration defines the minimum versions for Terraform and required providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Google Cloud Provider for managing GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    
    # Google Cloud Beta Provider for newer features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    
    # Archive provider for packaging Cloud Function source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Configure the Google Cloud Provider with default region and zone
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider for advanced features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}