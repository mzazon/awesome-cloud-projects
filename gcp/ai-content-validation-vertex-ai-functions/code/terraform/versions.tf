# Terraform and Provider Version Requirements
# This file specifies the minimum required versions for Terraform and providers
# to ensure compatibility and access to required features for AI content validation

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Google Cloud Provider for managing GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Beta Provider for preview features and newer API versions
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Archive provider for creating function source code archives
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}