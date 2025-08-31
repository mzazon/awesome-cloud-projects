# Terraform and provider version requirements
# This file specifies the minimum Terraform version and required providers
# for the Website Screenshot API infrastructure

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Cloud Beta Provider for advanced features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}