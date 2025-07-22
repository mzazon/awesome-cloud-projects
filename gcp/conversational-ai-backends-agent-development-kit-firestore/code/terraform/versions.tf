# Terraform configuration for Conversational AI Backends with Agent Development Kit and Firestore
# This configuration requires Terraform >= 1.0 and uses the latest stable provider versions

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Google Cloud Provider for core GCP services
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Beta Provider for preview features like Agent Development Kit
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Archive provider for packaging Cloud Functions source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Local provider for managing local files
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Configure the Google Cloud Provider with default project and region
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}