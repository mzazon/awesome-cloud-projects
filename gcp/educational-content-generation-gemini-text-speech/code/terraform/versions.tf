# Terraform and provider version requirements for Educational Content Generation Infrastructure
# This file defines the minimum required versions for Terraform and all providers

terraform {
  # Require Terraform version 1.5 or higher for advanced features and stability
  required_version = ">= 1.5"
  
  # Define required providers with specific version constraints
  required_providers {
    # Google Cloud Provider for GCP resource management
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"  # Use the latest 6.x version for new features and bug fixes
    }
    
    # Google Beta Provider for preview features and advanced configurations
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"  # Keep in sync with main Google provider
    }
    
    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"  # Stable version for random ID generation
    }
    
    # Archive provider for creating ZIP files for Cloud Function deployment
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"  # Latest stable version for file archiving
    }
    
    # Local provider for managing local files and templates
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"  # For local file management and templating
    }
  }
}

# Configure the Google Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  
  # Default labels applied to all resources managed by this provider
  default_labels = {
    managed_by  = "terraform"
    project     = "educational-content-generation"
    recipe_id   = "ed7f9a2b"
    environment = var.environment
  }
  
  # Enable request reason for better audit logging
  request_reason = "Educational Content Generation Infrastructure Deployment"
}

# Configure the Google Beta Provider for advanced features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  
  # Use beta provider for cutting-edge features while maintaining stability
  default_labels = {
    managed_by  = "terraform"
    project     = "educational-content-generation"
    recipe_id   = "ed7f9a2b"
    environment = var.environment
  }
}

# Configure the Random Provider
provider "random" {
  # No additional configuration required for random provider
}

# Configure the Archive Provider  
provider "archive" {
  # No additional configuration required for archive provider
}

# Configure the Local Provider
provider "local" {
  # No additional configuration required for local provider
}