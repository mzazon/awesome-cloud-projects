# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers
# to ensure compatibility with the resources and features used in this configuration.

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Google Cloud Provider - Main provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.9"
    }
    
    # Google Cloud Beta Provider - For preview/beta features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.9"
    }
    
    # Random Provider - For generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Time Provider - For time-based resource management
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

# Configure the Google Cloud Beta Provider
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}