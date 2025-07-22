# Terraform and Provider Version Constraints
# This file defines the required Terraform version and provider versions
# for the GCP Edge Caching Performance with CDN and Memorystore recipe

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider for features in beta
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Random Provider for generating unique suffixes
provider "random" {
  # No configuration needed
}