# =====================================
# Terraform and Provider Version Requirements
# for Adaptive Marketing Campaign Intelligence
# with Vertex AI Agents and Google Workspace Flows
# =====================================

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5.0"
  
  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider (primary)
    google = {
      source  = "hashicorp/google"
      version = "~> 6.33"
    }
    
    # Google Cloud Platform Beta provider (for preview features)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.33"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Template provider for file templating (if needed)
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
    
    # Time provider for time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
  
  # Backend configuration (uncomment and modify as needed)
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "marketing-intelligence"
  # }
}

# =====================================
# Provider Configuration
# =====================================

# Primary Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  
  # Enable user project override for quota and billing
  user_project_override = true
  
  # Set request timeout for long-running operations
  request_timeout = "60s"
  
  # Additional configuration for better error handling
  request_reason = "terraform-marketing-intelligence"
}

# Google Cloud Beta provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  
  # Enable user project override for quota and billing
  user_project_override = true
  
  # Set request timeout for long-running operations
  request_timeout = "60s"
  
  # Additional configuration for better error handling
  request_reason = "terraform-marketing-intelligence-beta"
}

# Random provider configuration
provider "random" {
  # No specific configuration needed
}

# Template provider configuration
provider "template" {
  # No specific configuration needed
}

# Time provider configuration
provider "time" {
  # No specific configuration needed
}