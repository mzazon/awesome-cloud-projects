# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0, < 6.0.0"
    }
    
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0.0, < 6.0.0"
    }
    
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0"
    }
    
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.2.0"
    }
  }
}

# Google Provider Configuration
provider "google" {
  project = var.project_id
  region  = var.region
  
  # Enable request/response logging for debugging (disable in production)
  request_timeout = "60s"
  
  # Default labels applied to all resources
  default_labels = merge(
    {
      environment = var.environment
      managed-by  = "terraform"
      purpose     = "bias-detection"
    },
    var.labels
  )
}

# Google Beta Provider Configuration (for beta features)
provider "google-beta" {
  project = var.project_id
  region  = var.region
  
  request_timeout = "60s"
  
  default_labels = merge(
    {
      environment = var.environment
      managed-by  = "terraform"
      purpose     = "bias-detection"
    },
    var.labels
  )
}

# Random Provider Configuration
provider "random" {
  # No specific configuration required
}

# Archive Provider Configuration  
provider "archive" {
  # No specific configuration required
}