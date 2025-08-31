# versions.tf - Provider version constraints and requirements
#
# This file defines the Terraform version requirements and provider configurations
# for the Weather Dashboard with Cloud Functions and Storage infrastructure.

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5"

  # Required providers with version constraints
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Archive provider for creating deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region

  # Enable user project override for better service account handling
  user_project_override = true
  
  # Enable request timeout for better reliability
  request_timeout = "60s"
}