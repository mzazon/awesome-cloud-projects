# Terraform and Provider Version Configuration
# This file defines the required Terraform version and provider versions
# for the automated event creation with Apps Script and Calendar API solution

terraform {
  # Require Terraform version 1.0 or later for modern features
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Provider for managing GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Time provider for managing time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable additional scopes for Google Workspace integration
  scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/calendar",
    "https://www.googleapis.com/auth/script.projects",
    "https://www.googleapis.com/auth/gmail.send"
  ]
}

# Configure the Random Provider
provider "random" {}

# Configure the Time Provider
provider "time" {}