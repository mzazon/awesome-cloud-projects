# Terraform and provider version requirements for GCP compliance reporting solution
terraform {
  required_version = ">= 1.8.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.2"
    }
  }
}

# Configure the Google Cloud provider with default project and region
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta provider for newer features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}