# Terraform version and provider requirements for AI-Powered Cost Analytics solution
# This configuration defines the minimum required versions for Terraform and providers

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

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider for features in beta
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Random Provider for generating unique suffixes
provider "random" {}