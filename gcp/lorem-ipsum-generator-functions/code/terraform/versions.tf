# Terraform and provider version requirements for the Lorem Ipsum Generator Cloud Functions recipe
# This configuration ensures consistent deployment across different environments

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.45"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the Google Cloud Provider
# Note: Authentication should be configured via environment variables or service account key
provider "google" {
  project = var.project_id
  region  = var.region
}