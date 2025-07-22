# Terraform and Provider Version Requirements
# This file defines the minimum versions for Terraform and required providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Google Cloud Provider for core GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Cloud Beta Provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Archive provider for packaging Cloud Function source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Null provider for local-exec provisioners
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}