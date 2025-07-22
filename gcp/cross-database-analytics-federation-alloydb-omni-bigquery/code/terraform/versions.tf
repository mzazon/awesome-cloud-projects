# Provider and Terraform version requirements for Cross-Database Analytics Federation
# This file defines the minimum versions and provider configurations required

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.10"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
  
  # Terraform Cloud and Enterprise compatibility
  backend "gcs" {
    # Uncomment and configure for remote state storage
    # bucket = "your-terraform-state-bucket"
    # prefix = "analytics-federation"
  }
}

# Google Cloud Provider Configuration
provider "google" {
  # Project, region, and zone can be set via variables or environment variables
  # GOOGLE_PROJECT, GOOGLE_REGION, GOOGLE_ZONE
  
  # Optional: Default labels for all resources
  default_labels = {
    created-by    = "terraform"
    managed-by    = "terraform"
    project-type  = "analytics-federation"
  }
  
  # Optional: Request timeout
  request_timeout = "60s"
  
  # Optional: Batching configuration for API requests
  batching {
    send_after      = "10s"
    enable_batching = true
  }
}

# Google Cloud Beta Provider for preview features
provider "google-beta" {
  # Same configuration as the stable provider
  # Used for accessing beta features and services
  
  default_labels = {
    created-by    = "terraform"
    managed-by    = "terraform"
    project-type  = "analytics-federation"
  }
  
  request_timeout = "60s"
  
  batching {
    send_after      = "10s"
    enable_batching = true
  }
}

# Random provider for generating unique identifiers
provider "random" {
  # No special configuration required
}

# Archive provider for creating function source archives
provider "archive" {
  # No special configuration required
}