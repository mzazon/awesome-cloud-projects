# Terraform and Provider Version Requirements
# This file specifies the required versions for Terraform and providers
# to ensure compatibility and reproducible deployments

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Google Cloud Provider for core GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    
    # Google Cloud Beta Provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Local provider for local value processing
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    
    # Null provider for provisioner actions
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    
    # Time provider for time-based resources
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
  
  # Optional: Configure remote state backend
  # Uncomment and configure for production deployments
  # backend "gcs" {
  #   bucket  = "your-terraform-state-bucket"
  #   prefix  = "multi-stream-data-processing"
  # }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = "${var.region}-a"
  
  # Enable request logging for debugging (disable in production)
  request_timeout = "60s"
  
  # Batch requests for better performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }
  
  # Default labels for all resources
  default_labels = {
    managed_by = "terraform"
    project    = "multi-stream-data-processing"
    team       = "data-engineering"
  }
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = "${var.region}-a"
  
  # Enable request logging for debugging (disable in production)
  request_timeout = "60s"
  
  # Batch requests for better performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }
  
  # Default labels for all resources
  default_labels = {
    managed_by = "terraform"
    project    = "multi-stream-data-processing"
    team       = "data-engineering"
  }
}

# Configure the Random Provider
provider "random" {
  # No specific configuration needed
}

# Configure the Local Provider
provider "local" {
  # No specific configuration needed
}

# Configure the Null Provider
provider "null" {
  # No specific configuration needed
}

# Configure the Time Provider
provider "time" {
  # No specific configuration needed
}