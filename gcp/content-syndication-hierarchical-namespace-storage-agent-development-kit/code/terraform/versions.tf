# Terraform and Provider Requirements for Content Syndication Platform
# This configuration defines the minimum versions and provider sources for deploying
# a GCP-based content syndication platform with hierarchical namespace storage

terraform {
  required_version = ">= 1.5"

  required_providers {
    # Google Cloud Provider - primary provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44"
    }

    # Google Beta Provider - for preview features including Hierarchical Namespace Storage
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Archive provider for function source code packaging
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Primary Google Cloud Provider Configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable user project override for billing attribution
  user_project_override = true

  # Request timeout for long-running operations
  request_timeout = "60s"
}

# Google Beta Provider for Preview Features
# Used specifically for Hierarchical Namespace Storage and Agent Development Kit
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  user_project_override = true
  request_timeout       = "60s"
}