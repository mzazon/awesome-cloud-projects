# Terraform and Provider Version Requirements
# This file specifies the minimum versions required for Terraform and providers
# to ensure compatibility and access to the latest features

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Google Cloud Provider - Official provider for Google Cloud Platform
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    # Google Beta Provider - Access to beta features and resources
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    
    # Random Provider - Generate random values for unique resource naming
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Archive Provider - Create zip archives for Cloud Function source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Time Provider - Time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
  
  # Optional: Configure remote state backend
  # Uncomment and configure based on your state management strategy
  
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "compliance-monitoring/terraform.tfstate"
  # }
  
  # backend "remote" {
  #   organization = "your-terraform-cloud-org"
  #   workspaces {
  #     name = "compliance-monitoring"
  #   }
  # }
}

# Configure the Google Cloud Provider
provider "google" {
  # Project and region can be set via variables or environment variables
  # project = var.project_id  # Set via TF_VAR_project_id or in terraform.tfvars
  # region  = var.region      # Set via TF_VAR_region or in terraform.tfvars
  
  # Enable request batching for improved performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }
  
  # Configure user-agent for better tracking and support
  user_project_override = true
  billing_project       = var.project_id != "" ? var.project_id : null
}

# Configure the Google Beta Provider for beta features
provider "google-beta" {
  # project = var.project_id
  # region  = var.region
  
  batching {
    enable_batching = true
    send_after      = "10s"
  }
  
  user_project_override = true
  billing_project       = var.project_id != "" ? var.project_id : null
}

# Configure the Random Provider
provider "random" {
  # No additional configuration required
}

# Configure the Archive Provider
provider "archive" {
  # No additional configuration required
}

# Configure the Time Provider
provider "time" {
  # No additional configuration required
}