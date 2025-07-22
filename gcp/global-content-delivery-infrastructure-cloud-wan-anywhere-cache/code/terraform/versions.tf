# Terraform Provider Requirements
# This file specifies the required providers and minimum Terraform version
# for the Global Content Delivery Infrastructure recipe

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.0"

  # Required provider specifications
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Beta provider for advanced features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Random provider for generating unique identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Time provider for managing resource lifecycle timing
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.primary_region
}

# Configure the Google Cloud Beta Provider
provider "google-beta" {
  project = var.project_id
  region  = var.primary_region
}