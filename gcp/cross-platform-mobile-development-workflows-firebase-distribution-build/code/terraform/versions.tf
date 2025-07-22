# Terraform version and provider requirements
# for Cross-Platform Mobile Development Workflows with Firebase App Distribution and Cloud Build

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider
# Required for Firebase resources which are currently in beta
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Random provider for generating unique resource names
provider "random" {}