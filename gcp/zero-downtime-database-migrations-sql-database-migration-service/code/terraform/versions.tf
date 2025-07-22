# Terraform version and provider requirements for zero-downtime database migration
terraform {
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud provider for core GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44"
    }
    
    # Google Beta provider for Database Migration Service and advanced features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Time provider for managed resource timing and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# Configure the Google Cloud provider with authentication and project settings
provider "google" {
  project                     = var.project_id
  region                      = var.region
  zone                        = var.zone
  user_project_override       = true
  billing_project            = var.project_id
  add_terraform_attribution_label = true
}

# Configure the Google Beta provider for Database Migration Service
provider "google-beta" {
  project                     = var.project_id
  region                      = var.region
  zone                        = var.zone
  user_project_override       = true
  billing_project            = var.project_id
  add_terraform_attribution_label = true
}