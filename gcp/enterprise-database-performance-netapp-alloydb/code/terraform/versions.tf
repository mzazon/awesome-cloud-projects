# Terraform Provider Requirements
# This file defines the required providers and their versions for the enterprise database performance solution

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Google Cloud Provider for core GCP services
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Cloud Beta Provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    
    # Time provider for resource timing and delays
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
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}