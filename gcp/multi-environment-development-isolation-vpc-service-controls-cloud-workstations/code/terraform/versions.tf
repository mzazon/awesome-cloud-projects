# Terraform provider requirements for multi-environment development isolation solution
terraform {
  required_version = ">= 1.0"
  
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
      version = "~> 3.1"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.dev_project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider (for newer features)
provider "google-beta" {
  project = var.dev_project_id
  region  = var.region
  zone    = var.zone
}