# Terraform version and provider requirements
terraform {
  required_version = ">= 1.5"

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
      version = "~> 3.6"
    }
  }
}

# Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Google Cloud Beta provider for features in beta
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Random provider for generating unique suffixes
provider "random" {}