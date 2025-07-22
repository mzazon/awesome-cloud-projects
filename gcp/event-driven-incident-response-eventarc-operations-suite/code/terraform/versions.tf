# Terraform and Provider Configurations for Event-Driven Incident Response System
# This configuration supports Eventarc, Cloud Functions Gen 2, Cloud Run, and Cloud Operations Suite

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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels for all resources
  default_labels = {
    environment = var.environment
    project     = "incident-response"
    managed-by  = "terraform"
    recipe      = "event-driven-incident-response"
  }
}

# Configure the Google Cloud Beta Provider for newer features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels for all resources
  default_labels = {
    environment = var.environment
    project     = "incident-response"
    managed-by  = "terraform"
    recipe      = "event-driven-incident-response"
  }
}