# Terraform Provider Requirements for User Lifecycle Management with Firebase Auth and Cloud Tasks
# This configuration specifies the required Terraform and provider versions for the infrastructure

terraform {
  required_version = ">= 1.5"

  required_providers {
    # Google Cloud Platform provider for core infrastructure resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.12"
    }

    # Google Cloud Platform beta provider for Firebase and preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.12"
    }

    # Random provider for generating unique resource names and passwords
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Archive provider for packaging Cloud Run application source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Null provider for triggering local provisioners and custom logic
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Cloud Beta Provider for Firebase and preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}