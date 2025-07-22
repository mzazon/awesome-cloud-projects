# Terraform and Provider Version Requirements
# Remote Developer Onboarding with Cloud Workstations and Firebase Studio

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.12"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider for workstations
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Random Provider for unique naming
provider "random" {}

# Configure the Time Provider for resource delays
provider "time" {}