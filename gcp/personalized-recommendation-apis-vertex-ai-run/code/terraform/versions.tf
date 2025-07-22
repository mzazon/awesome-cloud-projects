# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers
# to ensure compatibility and access to the latest features for the ML recommendation system

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.6.0"
  
  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 6.40"
    }
    
    # Google Cloud Beta provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.40"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Time provider for time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    
    # Null provider for conditional resource creation
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    
    # Local provider for local computations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    
    # Template provider for file templating (if needed)
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }
  
  # Optional: Configure remote backend for state management
  # Uncomment and configure based on your state management requirements
  
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "terraform/personalized-recommendation-apis"
  # }
  
  # backend "local" {
  #   path = "terraform.tfstate"
  # }
}

# Configure the Google Cloud Provider
provider "google" {
  # Provider configuration is handled through environment variables or explicit configuration
  # Required environment variables:
  # - GOOGLE_PROJECT or project variable
  # - GOOGLE_REGION or region variable
  # - GOOGLE_APPLICATION_CREDENTIALS or service account key
  
  # Optional: Set default labels for all resources
  default_labels = {
    managed-by = "terraform"
    project    = "ml-recommendation-system"
  }
  
  # Optional: Configure user project override for billing
  user_project_override = true
  
  # Optional: Configure billing project for quota and billing
  billing_project = var.project_id
  
  # Optional: Configure request timeout
  request_timeout = "60s"
  
  # Optional: Configure request retry
  request_reason = "terraform-ml-recommendation-system"
}

# Configure the Google Cloud Beta Provider
provider "google-beta" {
  # Beta provider for accessing preview features
  # Uses the same configuration as the main Google provider
  
  # Optional: Set default labels for all resources
  default_labels = {
    managed-by = "terraform"
    project    = "ml-recommendation-system"
  }
  
  # Optional: Configure user project override for billing
  user_project_override = true
  
  # Optional: Configure billing project for quota and billing
  billing_project = var.project_id
  
  # Optional: Configure request timeout
  request_timeout = "60s"
  
  # Optional: Configure request retry
  request_reason = "terraform-ml-recommendation-system-beta"
}

# Configure the Random Provider
provider "random" {
  # Random provider doesn't require configuration
  # Used for generating unique resource names and identifiers
}

# Configure the Time Provider
provider "time" {
  # Time provider doesn't require configuration
  # Used for time-based operations and delays
}

# Configure the Null Provider
provider "null" {
  # Null provider doesn't require configuration
  # Used for conditional resource creation and local-exec provisioners
}

# Configure the Local Provider
provider "local" {
  # Local provider doesn't require configuration
  # Used for local file operations and computations
}

# Configure the Template Provider
provider "template" {
  # Template provider doesn't require configuration
  # Used for file templating operations
}

# Provider version constraints explanation:
# 
# Google Provider (~> 6.40):
# - Supports latest Vertex AI features including model deployment and endpoints
# - Includes Cloud Run gen2 execution environment support
# - Provides comprehensive BigQuery and Cloud Storage resource management
# - Supports latest IAM and service account configurations
# - Includes Cloud Build integration for CI/CD workflows
#
# Google Beta Provider (~> 6.40):
# - Provides access to preview features and early access APIs
# - Useful for testing new Vertex AI capabilities
# - May include enhanced monitoring and logging features
#
# Random Provider (~> 3.6):
# - Stable provider for generating unique identifiers
# - Supports various random string and number generation
# - Essential for creating globally unique resource names
#
# Time Provider (~> 0.12):
# - Provides time-based resource operations
# - Useful for adding delays in resource creation
# - Supports time-based conditional logic
#
# Null Provider (~> 3.2):
# - Enables conditional resource creation patterns
# - Supports local-exec provisioners for custom scripts
# - Useful for complex deployment orchestration
#
# Local Provider (~> 2.5):
# - Handles local file operations
# - Supports local computations and data processing
# - Useful for generating configuration files
#
# Template Provider (~> 2.2):
# - Provides file templating capabilities
# - Useful for generating configuration files from templates
# - Supports variable substitution in templates

# Terraform version constraints explanation:
#
# Terraform >= 1.6.0:
# - Supports latest HCL syntax and features
# - Includes improved error handling and validation
# - Provides better state management and locking
# - Supports advanced for_each and conditional expressions
# - Includes enhanced provider configuration options
# - Provides improved debugging and logging capabilities
#
# Features used in this configuration that require Terraform >= 1.6.0:
# - Advanced variable validation with multiple conditions
# - Dynamic blocks with complex expressions
# - Optional object attributes with default values
# - Sensitive output handling
# - Provider configuration with default_labels
# - Enhanced error messages and validation

# Backend configuration recommendations:
#
# For Production:
# - Use Google Cloud Storage (GCS) backend for state management
# - Enable state locking with Cloud Storage
# - Use separate buckets for different environments
# - Implement proper IAM permissions for state access
# - Enable versioning on state storage bucket
#
# For Development:
# - Local backend is acceptable for individual development
# - Consider using terraform workspaces for environment isolation
# - Ensure state files are not committed to version control
# - Use .terraform directory in .gitignore
#
# For Team Collaboration:
# - Use remote backend (GCS recommended for GCP)
# - Implement proper access controls and permissions
# - Use consistent naming conventions for state files
# - Consider using Terraform Cloud or Terraform Enterprise
# - Implement proper backup and recovery procedures

# Provider authentication recommendations:
#
# Service Account Key (Not recommended for production):
# - Set GOOGLE_APPLICATION_CREDENTIALS environment variable
# - Point to JSON service account key file
# - Ensure key files are not committed to version control
#
# Application Default Credentials (Recommended):
# - Use gcloud auth application-default login for development
# - Use workload identity for GKE deployments
# - Use compute engine service accounts for GCE deployments
# - Use Cloud Build service accounts for CI/CD pipelines
#
# Workload Identity Federation (Recommended for CI/CD):
# - Configure workload identity federation for GitHub Actions
# - Use short-lived tokens instead of long-lived keys
# - Implement proper OIDC trust relationships
# - Follow principle of least privilege for permissions

# Required Google Cloud APIs:
# The following APIs will be enabled automatically by this configuration:
# - AI Platform (Vertex AI): aiplatform.googleapis.com
# - Cloud Run: run.googleapis.com
# - Cloud Storage: storage.googleapis.com
# - BigQuery: bigquery.googleapis.com
# - Cloud Build: cloudbuild.googleapis.com
# - Container Registry: containerregistry.googleapis.com
# - IAM: iam.googleapis.com
# - Cloud Resource Manager: cloudresourcemanager.googleapis.com
#
# Additional APIs that may be needed:
# - Cloud Monitoring: monitoring.googleapis.com
# - Cloud Logging: logging.googleapis.com
# - Cloud KMS: cloudkms.googleapis.com (if using CMEK)
# - Compute Engine: compute.googleapis.com (if using VPC)
# - Cloud Functions: cloudfunctions.googleapis.com (if using Cloud Functions)

# Resource quotas and limits to consider:
#
# Vertex AI:
# - Training job limits per region
# - Model deployment limits
# - Endpoint limits per region
# - Prediction request limits
#
# Cloud Run:
# - Service limits per region
# - Concurrent request limits
# - Memory and CPU limits
# - Request timeout limits
#
# Cloud Storage:
# - Bucket limits per project
# - Object size limits
# - Request rate limits
# - Bandwidth limits
#
# BigQuery:
# - Dataset limits per project
# - Table limits per dataset
# - Query limits and quotas
# - Slot limits for queries
#
# General:
# - Project limits per organization
# - API request limits
# - Service account limits
# - IAM policy limits