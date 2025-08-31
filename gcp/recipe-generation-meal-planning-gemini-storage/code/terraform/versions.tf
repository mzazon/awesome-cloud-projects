# Terraform and Provider Version Requirements
# This file defines the required Terraform version and provider configurations
# for the Recipe Generation and Meal Planning system

terraform {
  # Require Terraform version 1.0 or higher for stable functionality
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Beta provider for preview features and newer APIs
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
      version = "~> 3.6"
    }
  }
}

# Configure the Google Cloud Provider
# This provider configuration applies to all google resources
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Beta Provider for preview features
# Used for services that may not be available in the stable provider
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}