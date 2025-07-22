# Terraform provider requirements for legacy application modernization
# This configuration defines the required providers and their minimum versions

terraform {
  required_version = ">= 1.5"
  
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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

# Google Cloud Provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Random provider for generating unique resource names
provider "random" {}

# Time provider for resource delays and timestamps
provider "time" {}