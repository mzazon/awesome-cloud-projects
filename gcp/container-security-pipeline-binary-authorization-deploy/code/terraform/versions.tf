# Terraform and Provider Version Constraints
# This file defines the minimum required versions for Terraform and the providers used

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider for newer features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Random provider for generating unique resource names
provider "random" {}

# Time provider for managing time-based resources
provider "time" {}