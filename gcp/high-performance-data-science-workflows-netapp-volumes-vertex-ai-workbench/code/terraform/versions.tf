# Terraform version and provider requirements for high-performance data science workflows
# Requires Google Cloud provider 6.44.0+ for latest NetApp Volumes and Vertex AI Workbench features

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

# Google Cloud provider configuration with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels for all resources created by this module
  default_labels = {
    environment = var.environment
    purpose     = "data-science-ml"
    recipe      = "high-performance-netapp-workbench"
    managed-by  = "terraform"
  }
}

# Random provider for generating unique resource names
provider "random" {}