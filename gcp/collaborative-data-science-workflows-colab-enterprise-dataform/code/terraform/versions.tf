# Terraform version and provider requirements for collaborative data science workflows

terraform {
  required_version = ">= 1.5"
  
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

# Configure the Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta provider for Dataform resources
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Random provider for generating unique identifiers
provider "random" {}