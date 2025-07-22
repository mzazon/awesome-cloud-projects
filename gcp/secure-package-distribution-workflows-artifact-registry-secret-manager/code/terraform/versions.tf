# Terraform and Provider Version Requirements
# This file specifies the minimum versions for Terraform and the Google Cloud Provider

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.26.0, < 7"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.26.0, < 7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Cloud Beta Provider for advanced features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Configure the Random Provider for generating unique identifiers
provider "random" {}