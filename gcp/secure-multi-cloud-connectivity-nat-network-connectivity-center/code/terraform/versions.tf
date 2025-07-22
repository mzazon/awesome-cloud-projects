# Terraform and Provider Version Requirements
# Version constraints for Secure Multi-Cloud Connectivity with Cloud NAT and Network Connectivity Center

terraform {
  required_version = ">= 1.6"
  
  required_providers {
    # Google Cloud Platform Provider
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    
    # Google Cloud Platform Beta Provider (for advanced features)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    
    # Random Provider for generating unique resource names
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

# Configure the Random Provider
provider "random" {
  # No additional configuration required
}