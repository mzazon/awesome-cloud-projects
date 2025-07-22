# Terraform version and provider requirements for multi-modal AI content generation pipeline
# This configuration ensures compatibility with the latest Google Cloud provider features
# including Vertex AI Agent Development Kit and Cloud Composer 2.x

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Google Cloud provider for core GCP services
    google = {
      source  = "hashicorp/google"
      version = "~> 5.10.0"
    }
    
    # Google Cloud Beta provider for advanced features like Vertex AI ADK
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.10.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    
    # Local provider for template rendering and local operations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4.0"
    }
    
    # Archive provider for packaging Cloud Run application code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }
  }
  
  # Optional: Configure backend for state storage in Cloud Storage
  # Uncomment and configure for production deployments
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "multi-modal-content-generation"
  # }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Enable request batching for improved performance
  batching {
    enable_batching = true
  }
}

# Configure the Google Cloud Beta Provider for advanced features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Enable request batching for improved performance
  batching {
    enable_batching = true
  }
}