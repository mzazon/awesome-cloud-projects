# Terraform and provider version requirements
# This file defines the minimum versions required for Terraform and providers

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Google Cloud Provider for main GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Cloud Beta Provider for preview/beta features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Time provider for managing resource creation delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider for Oracle Database@Google Cloud
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}