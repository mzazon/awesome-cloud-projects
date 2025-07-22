# ============================================================================
# Terraform and Provider Version Constraints
# ============================================================================
#
# This file defines the required Terraform version and provider versions
# to ensure consistent and reliable infrastructure deployments across
# different environments and team members.
#
# ============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Google Cloud Provider for standard resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Beta Provider for beta/preview resources (Dataform)
    google-beta = {
      source  = "hashicorp/google-beta"  
      version = "~> 6.0"
    }

    # Archive provider for creating ZIP files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Optional: Configure backend for state management
  # Uncomment and customize for production deployments
  # backend "gcs" {
  #   bucket  = "your-terraform-state-bucket"
  #   prefix  = "data-pipeline-recovery/terraform.tfstate"
  # }
}

# ============================================================================
# Provider Configuration
# ============================================================================

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region

  # Default labels applied to all resources
  default_labels = {
    terraform   = "true"
    environment = var.environment
    solution    = "data-pipeline-recovery"
  }

  # Additional provider configuration
  user_project_override = true
  billing_project       = var.project_id
}

# Configure the Google Cloud Beta Provider
provider "google-beta" {
  project = var.project_id
  region  = var.region

  # Default labels applied to all beta resources
  default_labels = {
    terraform   = "true"
    environment = var.environment
    solution    = "data-pipeline-recovery"
  }

  # Additional provider configuration
  user_project_override = true
  billing_project       = var.project_id
}

# Configure the Archive Provider
provider "archive" {
  # No specific configuration required
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required
}