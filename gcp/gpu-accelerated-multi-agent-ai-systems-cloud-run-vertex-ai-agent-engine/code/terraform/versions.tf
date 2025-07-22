# GPU-Accelerated Multi-Agent AI Systems - Terraform Version Requirements
# This file specifies the required Terraform and provider versions for the infrastructure

terraform {
  # Terraform version constraint
  required_version = ">= 1.5.0, < 2.0.0"
  
  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider - main provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44"
    }
    
    # Google Cloud Platform Beta provider - for preview/beta features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44"
    }
    
    # Random provider - for generating unique resource names and IDs
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Time provider - for managing time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
  
  # Backend configuration for Terraform state management
  # Uncomment and configure the backend block below for production deployments
  
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "multi-agent-ai/terraform.tfstate"
  #   
  #   # Optional: Enable state locking with Cloud Storage
  #   # Note: State locking for GCS backend requires additional configuration
  # }
  
  # Alternative backend configuration using local state (development only)
  # backend "local" {
  #   path = "./terraform.tfstate"
  # }
}

# Provider configurations with feature flags and experimental features

# Main Google Cloud provider configuration
provider "google" {
  # The project, region, and zone will be set via variables
  # These can also be set via environment variables:
  # - GOOGLE_PROJECT (or GOOGLE_CLOUD_PROJECT)
  # - GOOGLE_REGION
  # - GOOGLE_ZONE
  
  # User project override for quota and billing
  user_project_override = true
  
  # Default request timeout
  request_timeout = "60s"
  
  # Add any additional provider-level configuration here
}

# Google Cloud Beta provider for accessing preview features
provider "google-beta" {
  # Beta provider inherits settings from main provider
  # but enables access to beta/preview features
  
  user_project_override = true
  request_timeout = "60s"
}

# Provider feature flags for enhanced functionality
# These flags enable additional features that may be useful for AI workloads

# Enable Cloud Run v2 API (required for GPU support)
# This is handled through the google_project_service resource in main.tf

# Version compatibility notes:
# - Terraform >= 1.5.0: Required for enhanced validation and provider features
# - Google provider >= 6.44.0: Required for Cloud Run v2 GPU support and latest Vertex AI features
# - Google Beta provider >= 6.44.0: Required for preview AI and ML features
# - Random provider >= 3.6.0: Required for stable random ID generation
# - Time provider >= 0.12.0: Required for time-based resource management

# Important notes for production deployments:
# 1. Pin provider versions to specific versions rather than using ~> for production
# 2. Configure remote state backend (GCS recommended for GCP projects)
# 3. Enable state locking to prevent concurrent modifications
# 4. Use separate Terraform workspaces or directories for different environments
# 5. Regularly update provider versions to get security patches and new features

# Provider version update policy:
# - Major versions (e.g., 5.x to 6.x): Review breaking changes, test thoroughly
# - Minor versions (e.g., 6.44 to 6.45): Generally safe, but review changelog
# - Patch versions (e.g., 6.44.0 to 6.44.1): Safe to apply, usually bug fixes

# Compatibility matrix:
# ┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐
# │ Terraform       │ Google Provider │ Features        │ AI/ML Support   │
# ├─────────────────┼─────────────────┼─────────────────┼─────────────────┤
# │ >= 1.5.0        │ >= 6.44.0       │ Cloud Run v2    │ Full            │
# │ >= 1.4.0        │ >= 6.20.0       │ Cloud Run v1    │ Limited         │
# │ >= 1.3.0        │ >= 5.0.0        │ Basic resources │ Basic           │
# └─────────────────┴─────────────────┴─────────────────┴─────────────────┘

# GPU support requirements:
# - Cloud Run v2 API must be enabled
# - GPU quotas must be available in the selected region
# - Compatible GPU types: nvidia-l4, nvidia-t4
# - GPU-enabled regions: us-central1, us-east1, us-west1, europe-west1, etc.

# State management best practices:
# 1. Use Google Cloud Storage (GCS) backend for team collaboration
# 2. Enable versioning on the state bucket
# 3. Configure appropriate IAM permissions for state bucket access
# 4. Use encryption at rest and in transit for state files
# 5. Implement state locking to prevent corruption from concurrent access

# Example GCS backend configuration for production:
# terraform {
#   backend "gcs" {
#     bucket  = "your-org-terraform-state-prod"
#     prefix  = "projects/multi-agent-ai"
#     
#     # Optional: custom encryption key
#     # encryption_key = "your-kms-key"
#     
#     # Optional: state locking using Cloud Storage
#     # Note: GCS doesn't natively support state locking
#     # Consider using additional tools like terraform-backend-gcs with DynamoDB equivalent
#   }
# }

# Development vs Production considerations:
# Development:
# - Use local backend or simple GCS bucket
# - Allow ~> version constraints for easier updates
# - Enable experimental features for testing
# - Smaller resource quotas and limits

# Production:
# - Use GCS backend with encryption and versioning
# - Pin exact provider versions
# - Disable experimental features
# - Enable deletion protection
# - Implement proper monitoring and alerting
# - Use separate service accounts with minimal permissions