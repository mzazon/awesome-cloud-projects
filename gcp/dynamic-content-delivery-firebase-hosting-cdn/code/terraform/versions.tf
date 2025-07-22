# ==========================================
# Terraform and Provider Version Configuration
# ==========================================
# This file defines the required Terraform version and provider constraints
# for the Dynamic Content Delivery with Firebase Hosting and Cloud CDN recipe

terraform {
  # Specify minimum Terraform version for compatibility
  required_version = ">= 1.0"

  # Configure required providers with version constraints
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
      version = "~> 3.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# ==========================================
# Provider Configuration
# ==========================================

# Main Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

# Beta provider for resources that require beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}