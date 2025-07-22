# Healthcare Data Processing Terraform Configuration
# Provider version constraints and requirements

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
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Enable user project override for better quota management
  user_project_override = true
  
  # Set default labels for all resources
  default_labels = merge(var.labels, {
    terraform_managed = "true"
    recipe_name      = "healthcare-data-processing-batch-vertex-ai-agents"
    last_updated     = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Enable user project override for better quota management
  user_project_override = true
  
  # Set default labels for all resources
  default_labels = merge(var.labels, {
    terraform_managed = "true"
    recipe_name      = "healthcare-data-processing-batch-vertex-ai-agents"
    last_updated     = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Configure the Random Provider
provider "random" {
  # No configuration needed
}

# Configure the Archive Provider
provider "archive" {
  # No configuration needed
}