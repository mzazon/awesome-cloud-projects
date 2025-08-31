# Terraform version and provider requirements for GCP Task Manager
# This configuration ensures compatibility with Google Cloud Provider features
# and maintains infrastructure consistency across environments

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Google Cloud Provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Archive provider for creating function source code zip files
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Random provider for unique resource naming
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Google Cloud Provider with project and region defaults
provider "google" {
  project = var.project_id
  region  = var.region
}