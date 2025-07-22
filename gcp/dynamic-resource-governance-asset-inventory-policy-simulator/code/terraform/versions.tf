# Terraform and Provider Version Requirements
# This file defines the minimum versions required for Terraform and providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Cloud Platform Beta provider for newer features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    
    # Archive provider for creating ZIP files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider for newer features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}