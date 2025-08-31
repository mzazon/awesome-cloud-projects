# Terraform configuration and provider requirements for Location-Aware Content Generation
# This file defines the required Terraform version and Google Cloud provider configuration

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Google Cloud Provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Cloud Beta Provider for preview features like Maps grounding
    google-beta = {
      source  = "hashicorp/google-beta" 
      version = "~> 5.0"
    }
    
    # Archive provider for creating Cloud Function source code archives
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Random provider for generating unique resource suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Google Cloud Provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}