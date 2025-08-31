# Provider version constraints for App Engine deployment
# This configuration specifies the required Terraform and provider versions
# to ensure consistent behavior across different environments

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Google Cloud Platform provider for managing GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Archive provider for creating zip files of application code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
}