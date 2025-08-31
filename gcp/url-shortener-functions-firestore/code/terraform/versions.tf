# Terraform and Provider Version Requirements
# Defines the minimum versions required for Terraform and Google Cloud Provider

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Google Cloud Provider Configuration
# Configure the Google Cloud Provider with project and region defaults
provider "google" {
  project = var.project_id
  region  = var.region

  # Default labels to apply to all resources
  default_labels = var.resource_labels
}