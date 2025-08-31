# Terraform and provider version requirements
# This file defines the minimum required versions for Terraform and the Google Cloud provider

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}