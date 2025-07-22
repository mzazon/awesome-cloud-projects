# Terraform version and provider requirements
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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

# Google Cloud Beta provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}