# Terraform provider configuration for Global Web Application Performance
# with Firebase App Hosting and Cloud CDN
#
# This configuration requires:
# - Terraform >= 1.5.0
# - Google Cloud provider >= 6.44.0
# - Google Cloud Beta provider >= 6.44.0 (for Firebase App Hosting features)

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Google Cloud provider for core infrastructure resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44"
    }

    # Google Cloud Beta provider for Firebase App Hosting and latest features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Archive provider for packaging Cloud Functions source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all resources
  default_labels = {
    environment = var.environment
    recipe      = "global-web-app-performance"
    managed-by  = "terraform"
  }
}

# Configure the Google Cloud Beta provider for Firebase App Hosting
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all resources
  default_labels = {
    environment = var.environment
    recipe      = "global-web-app-performance"
    managed-by  = "terraform"
  }
}