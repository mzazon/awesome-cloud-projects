# Smart Parking Management - Terraform Version Configuration
# Defines the Terraform and provider version requirements for Google Cloud Platform

terraform {
  # Require Terraform version 1.0 or higher for best practice features
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # Google Cloud Platform provider for core infrastructure
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Beta provider for accessing preview features and newer APIs
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    
    # Archive provider for creating ZIP files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Template provider for generating dynamic configuration files
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable request/response logging for debugging (disable in production)
  request_timeout = "60s"
}

# Configure the Google Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable request/response logging for debugging (disable in production)
  request_timeout = "60s"
}

# Configure the Random provider for deterministic results in testing
provider "random" {
  # No configuration needed for random provider
}

# Configure the Archive provider for creating deployment packages
provider "archive" {
  # No configuration needed for archive provider
}

# Configure the Template provider for dynamic file generation
provider "template" {
  # No configuration needed for template provider
}