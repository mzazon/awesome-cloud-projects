# Terraform and Provider Version Requirements
# GCP Personal Productivity Assistant with Gemini and Functions

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.6.0"
  
  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 5.11.0"
    }
    
    # Google Cloud Platform Beta provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.11.0"
    }
    
    # Archive provider for function source code packaging
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }
    
    # Random provider for unique resource naming
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    
    # Null provider for conditional resource creation
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
    
    # Time provider for time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10.0"
    }
  }
  
  # Backend configuration - uncomment and customize as needed
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "personal-productivity-assistant"
  # }
  
  # Alternative backend configurations:
  
  # Remote backend for Terraform Cloud
  # backend "remote" {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "personal-productivity-assistant"
  #   }
  # }
  
  # Local backend for development (default)
  # backend "local" {
  #   path = "terraform.tfstate"
  # }
  
  # Experimental features (if needed)
  # experiments = []
}

# Default provider configuration for Google Cloud
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Default labels applied to all resources
  default_labels = {
    managed-by    = "terraform"
    project-name  = "personal-productivity-assistant"
    recipe-id     = "b4f7e2a8"
    environment   = var.environment
  }
  
  # Request/response logging for debugging (disable in production)
  request_timeout = "60s"
  
  # User project override for quota and billing
  user_project_override = true
  
  # Batch requests for better performance
  batching {
    enable_batching = true
    send_after      = "5s"
  }
}

# Beta provider configuration for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Default labels applied to all resources
  default_labels = {
    managed-by    = "terraform"
    project-name  = "personal-productivity-assistant"
    recipe-id     = "b4f7e2a8"
    environment   = var.environment
  }
  
  # Request/response logging for debugging (disable in production)
  request_timeout = "60s"
  
  # User project override for quota and billing
  user_project_override = true
  
  # Batch requests for better performance
  batching {
    enable_batching = true
    send_after      = "5s"
  }
}

# Archive provider for packaging function source code
provider "archive" {
  # No specific configuration required
}

# Random provider for generating unique identifiers
provider "random" {
  # No specific configuration required
}

# Null provider for conditional operations
provider "null" {
  # No specific configuration required
}

# Time provider for time-based resources
provider "time" {
  # No specific configuration required
}

# Provider feature flags and experimental features
# Configure provider-specific features as needed

# Google provider features
# Enable specific APIs or features that are in preview
# provider "google" {
#   # Example: Enable new Cloud Functions generation 2
#   # features = {
#   #   cloud_functions_generation_2 = true
#   # }
# }

# Version constraints explanation:
# ~> 5.11.0 means >= 5.11.0 and < 5.12.0 (patch-level updates allowed)
# This provides stability while allowing bug fixes and security updates

# Recommended Terraform version lifecycle:
# - Development: Use latest stable version (>= 1.6.0)
# - Staging: Pin to specific version for consistency
# - Production: Pin to specific tested version

# Provider version upgrade strategy:
# 1. Test upgrades in development environment first
# 2. Review provider changelog for breaking changes
# 3. Update version constraints gradually
# 4. Test thoroughly before promoting to production

# Backend considerations:
# - Use remote backend (GCS, Terraform Cloud) for team collaboration
# - Enable state locking to prevent concurrent modifications
# - Regularly backup state files
# - Use separate state files for different environments

# Security considerations:
# - Store provider credentials securely (avoid hardcoding)
# - Use service accounts with minimal required permissions
# - Enable audit logging for Terraform operations
# - Regularly rotate access keys and tokens

# Performance optimization:
# - Enable provider batching for bulk operations
# - Use data sources efficiently to minimize API calls
# - Implement proper dependency management
# - Consider using parallelism settings for large deployments