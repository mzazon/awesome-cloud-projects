# Terraform and Provider Version Requirements
# This file defines the minimum versions required for Terraform and all providers
# to ensure compatibility and access to the latest features

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 5.10"
    }
    
    # Google Cloud Platform Beta provider (for Firebase and newer services)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.10"
    }
    
    # Random provider for generating unique identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Archive provider for creating ZIP files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Google Cloud Provider Configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Default labels applied to all resources
  default_labels = merge(
    {
      environment = var.environment
      managed-by  = "terraform"
      project     = "qa-workflows"
    },
    var.custom_labels
  )
}

# Google Cloud Beta Provider Configuration
# Required for Firebase services and other beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Default labels applied to all resources
  default_labels = merge(
    {
      environment = var.environment
      managed-by  = "terraform"
      project     = "qa-workflows"
    },
    var.custom_labels
  )
}