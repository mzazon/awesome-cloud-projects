# Terraform and Provider Version Constraints
# This file defines the required versions for Terraform and all providers

terraform {
  required_version = ">= 1.5.0"
  
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
      version = "~> 3.4"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Enable request/response logging for debugging (optional)
  # request_timeout = "60s"
  
  # Default labels to apply to all resources
  default_labels = {
    terraform   = "true"
    environment = var.environment
    recipe      = "network-security-monitoring"
  }
}

# Configure the Google Cloud Beta Provider for beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Default labels to apply to all resources
  default_labels = {
    terraform   = "true"
    environment = var.environment
    recipe      = "network-security-monitoring"
  }
}

# Configure the Random Provider
provider "random" {
  # No specific configuration needed
}