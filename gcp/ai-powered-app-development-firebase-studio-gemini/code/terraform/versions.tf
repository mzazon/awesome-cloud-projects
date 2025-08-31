# Terraform version and provider requirements for AI-Powered App Development
# This configuration defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Google Cloud Provider for core GCP services
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Beta Provider for experimental features and Firebase services
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    
    # Time provider for resource creation delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  
  # Enable request batching for better performance
  batching {
    send_after      = "10s"
    enable_batching = true
  }
}

# Configure the Google Beta Provider for Firebase services
provider "google-beta" {
  project = var.project_id
  region  = var.region
  
  # Enable request batching for better performance
  batching {
    send_after      = "10s"
    enable_batching = true
  }
}