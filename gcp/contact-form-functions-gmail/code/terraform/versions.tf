# Terraform provider requirements for GCP Contact Form with Cloud Functions and Gmail API
# This file defines the required providers and their version constraints

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Google Cloud Provider for managing GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Beta Provider for accessing beta features
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

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Beta Provider for beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}