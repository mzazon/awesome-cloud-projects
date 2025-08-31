# ================================================================
# Provider Requirements and Version Constraints
# ================================================================
# This file defines the Terraform version requirements and
# provider version constraints for the content quality scoring
# system infrastructure.
# ================================================================

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.6.0"
  
  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 5.44.0"
    }
    
    # Google Cloud Platform Beta provider for advanced features
    google-beta = {
      source  = "hashicorp/google-beta" 
      version = "~> 5.44.0"
    }
    
    # Archive provider for creating function source ZIP files
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    
    # Local provider for creating local files
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.0"
    }
    
    # Null provider for executing local commands
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
  }
  
  # Optional: Configure remote state backend
  # Uncomment and configure based on your requirements
  /*
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "content-quality-scoring"
  }
  */
  
  # Optional: Experimental features
  # experiments = []
}

# ================================================================
# Provider Configurations
# ================================================================

# Default Google Cloud provider configuration
provider "google" {
  # Project and region are configured via variables
  # Additional provider-level configuration can be added here
  
  # Default labels for all resources
  default_labels = {
    managed-by = "terraform"
    project    = "content-quality-scoring"
  }
  
  # User project override for billing
  user_project_override = true
  
  # Request timeout
  request_timeout = "60s"
}

# Google Cloud Beta provider for accessing beta features
provider "google-beta" {
  # Project and region are configured via variables
  # This provider enables access to beta/preview features
  
  # Default labels for all resources
  default_labels = {
    managed-by = "terraform"
    project    = "content-quality-scoring"
  }
  
  # User project override for billing
  user_project_override = true
  
  # Request timeout
  request_timeout = "60s"
}

# Archive provider for creating ZIP files
provider "archive" {
  # No additional configuration required
}

# Random provider for generating unique values
provider "random" {
  # No additional configuration required
}

# Local provider for local file operations
provider "local" {
  # No additional configuration required
}

# Null provider for local command execution
provider "null" {
  # No additional configuration required
}

# ================================================================
# Version Requirements Details
# ================================================================

# Terraform Version:
# - Minimum 1.6.0 for latest features and stability
# - Supports advanced variable validation
# - Includes improved provider dependency management

# Google Provider Version:
# - Version ~> 5.44.0 includes latest GCP resource support
# - Supports Cloud Functions 2nd generation
# - Includes Vertex AI resource management
# - Provides comprehensive IAM and security features

# Google Beta Provider Version:
# - Same version as main provider for consistency
# - Enables access to preview/beta GCP features
# - Required for some advanced Cloud Functions features

# Archive Provider Version:
# - Version ~> 2.4.0 for stable ZIP file creation
# - Supports proper file permissions and metadata
# - Includes content-based change detection

# Random Provider Version:
# - Version ~> 3.6.0 for cryptographically secure random values
# - Supports multiple random value types
# - Provides deterministic randomness with seeds

# Local Provider Version:
# - Version ~> 2.5.0 for local file management
# - Supports template rendering and file creation
# - Enables sensitive file handling

# Null Provider Version:
# - Version ~> 3.2.0 for local command execution
# - Provides reliable provisioner alternatives
# - Supports dependency management for local operations

# ================================================================
# Backend Configuration Notes
# ================================================================

# For production deployments, consider using a remote backend:
# 
# 1. Google Cloud Storage Backend:
#    - Provides state locking and versioning
#    - Integrates with Google Cloud IAM
#    - Supports encryption at rest
#
# 2. Terraform Cloud Backend:
#    - Includes remote execution and collaboration
#    - Provides state management and policy enforcement
#    - Supports automated deployments
#
# 3. Local Backend (default):
#    - Stores state locally (terraform.tfstate)
#    - Suitable for development and testing
#    - Requires manual state management

# ================================================================
# Provider Feature Requirements
# ================================================================

# This configuration requires the following provider features:
#
# Google Provider:
# - Cloud Functions 2nd generation support
# - Cloud Storage bucket management
# - IAM role and policy management
# - Service account creation and management
# - Project service enablement
# - Cloud Monitoring and alerting
#
# Google Beta Provider:
# - Advanced Cloud Functions configurations
# - Preview feature access
#
# Archive Provider:
# - ZIP file creation from source directories
# - Content hashing for change detection
#
# Random Provider:
# - Cryptographically secure random ID generation
# - Deterministic randomness for resource naming
#
# Local Provider:
# - Template file rendering
# - Local file creation and management
#
# Null Provider:
# - Local command execution
# - Directory creation and management

# ================================================================
# Compatibility Notes
# ================================================================

# Operating System Compatibility:
# - Linux (Ubuntu, CentOS, Amazon Linux)
# - macOS (Intel and Apple Silicon)
# - Windows (with WSL recommended)
#
# Terraform CLI Compatibility:
# - Terraform 1.6.0 and later
# - Terraform Cloud/Enterprise
# - Terragrunt (for advanced configurations)
#
# Google Cloud SDK Compatibility:
# - gcloud CLI version 450.0.0 or later
# - Application Default Credentials (ADC)
# - Service account key authentication