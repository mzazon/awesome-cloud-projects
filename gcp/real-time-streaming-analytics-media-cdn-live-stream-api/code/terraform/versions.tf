# Terraform version and provider requirements for GCP streaming analytics infrastructure
# This configuration ensures compatibility with the latest GCP provider features

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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Backend configuration for state management
  # Uncomment and configure for production use
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "terraform/streaming-analytics"
  # }
}

# Primary provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable additional APIs that may be required
  user_project_override = true
}

# Beta provider for accessing preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  user_project_override = true
}

# Random provider for generating unique resource names
provider "random" {}

# Archive provider for packaging Cloud Function source code
provider "archive" {}