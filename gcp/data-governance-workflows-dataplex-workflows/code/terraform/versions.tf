# Terraform and Provider Version Requirements
# This file specifies the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Beta provider for newer features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Random provider for generating unique suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Archive provider for function source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Null provider for local provisioners
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    # Time provider for time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# Provider configuration for Google Cloud
provider "google" {
  project = var.project_id
  region  = var.region
  
  # Default labels for all resources
  default_labels = merge(
    {
      managed_by      = "terraform"
      recipe          = "data-governance-workflows"
      environment     = var.environment
      creation_date   = formatdate("YYYY-MM-DD", timestamp())
    },
    var.labels
  )
}

# Provider configuration for Google Cloud Beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  
  # Default labels for all resources
  default_labels = merge(
    {
      managed_by      = "terraform"
      recipe          = "data-governance-workflows"
      environment     = var.environment
      creation_date   = formatdate("YYYY-MM-DD", timestamp())
    },
    var.labels
  )
}

# Provider configuration for Random
provider "random" {
  # Random provider doesn't require explicit configuration
}

# Provider configuration for Archive
provider "archive" {
  # Archive provider doesn't require explicit configuration
}

# Provider configuration for Null
provider "null" {
  # Null provider doesn't require explicit configuration
}

# Provider configuration for Time
provider "time" {
  # Time provider doesn't require explicit configuration
}