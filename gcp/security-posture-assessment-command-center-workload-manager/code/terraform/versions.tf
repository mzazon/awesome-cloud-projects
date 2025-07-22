# Terraform and Provider Version Constraints
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Default provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

# Beta provider for features not yet in stable API
provider "google-beta" {
  project = var.project_id
  region  = var.region
}