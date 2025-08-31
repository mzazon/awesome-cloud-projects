# Terraform version and provider requirements
# This file defines the minimum Terraform version and required providers
# for the Weather API Gateway infrastructure deployment

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Google Cloud Platform provider for managing GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}