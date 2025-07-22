# Terraform version and provider requirements for GCP multi-region backup automation
# This configuration specifies the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.5"

  required_providers {
    # Google Cloud Provider - Official provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Beta Provider - For beta features and resources
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }

    # Local provider for reading local files and template rendering
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Template provider for processing workflow definitions
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }
}

# Configure the Google Cloud Provider with project and region defaults
provider "google" {
  project = var.project_id
  region  = var.primary_region
}

# Configure the Google Cloud Beta Provider for beta features
provider "google-beta" {
  project = var.project_id
  region  = var.primary_region
}