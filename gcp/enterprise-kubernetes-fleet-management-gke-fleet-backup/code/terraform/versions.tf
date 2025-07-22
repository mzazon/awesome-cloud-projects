# Terraform version and provider requirements for GCP Enterprise Kubernetes Fleet Management
# This configuration defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    # Google Cloud Provider for core GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Beta Provider for preview features and advanced configurations
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Time provider for resource creation delays and timing
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  region = var.region
  zone   = var.zone
}

# Configure the Google Beta Provider for advanced features
provider "google-beta" {
  region = var.region
  zone   = var.zone
}