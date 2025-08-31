# =============================================================================
# Provider and Terraform Version Requirements
# =============================================================================
# This file defines the required Terraform version and provider versions
# for the Job Description Generation with Gemini and Firestore infrastructure.
# =============================================================================

terraform {
  # Require Terraform version 1.3 or later for optimal functionality
  required_version = ">= 1.3"
  
  # Required providers with version constraints
  required_providers {
    # Google Cloud Provider - Primary provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    
    # Google Cloud Beta Provider - For beta features (if needed)
    google-beta = {
      source  = "hashicorp/google-beta" 
      version = "~> 6.0"
    }
    
    # Archive Provider - For creating function source code zip files
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Time Provider - For managing resource dependencies with delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    
    # Random Provider - For generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  
  # Optional: Configure backend for state management
  # Uncomment and configure for production deployments
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "job-description-generator"
  # }
}

# =============================================================================
# Google Cloud Provider Configuration
# =============================================================================

# Primary Google Cloud provider configuration
provider "google" {
  # Project and region can be set via variables or environment variables
  # project = var.project_id  # Set via variable
  # region  = var.region      # Set via variable
  
  # Default labels applied to all resources created by this provider
  default_labels = {
    managed_by = "terraform"
    project    = "job-description-generator"
  }
  
  # Optional: Set user project override for billing
  # user_project_override = true
  
  # Optional: Configure request timeout
  request_timeout = "60s"
  
  # Optional: Configure retry settings
  request_reason = "terraform-deployment"
}

# Beta provider for accessing beta features
provider "google-beta" {
  # Project and region configuration
  # project = var.project_id  # Set via variable
  # region  = var.region      # Set via variable
  
  # Default labels for beta resources
  default_labels = {
    managed_by = "terraform"
    project    = "job-description-generator"
    provider   = "google-beta"
  }
  
  # Request configuration
  request_timeout = "60s"
  request_reason = "terraform-deployment-beta"
}

# =============================================================================
# Archive Provider Configuration
# =============================================================================

provider "archive" {
  # No specific configuration required for archive provider
}

# =============================================================================
# Time Provider Configuration  
# =============================================================================

provider "time" {
  # No specific configuration required for time provider
}

# =============================================================================
# Random Provider Configuration
# =============================================================================

provider "random" {
  # No specific configuration required for random provider
}

# =============================================================================
# Provider Version Compatibility Notes
# =============================================================================

# Google Cloud Provider v6.x includes:
# - Support for latest Cloud Functions (2nd gen) features
# - Full Firestore Native mode support
# - Enhanced Vertex AI integration
# - Improved IAM and security features
# - Better resource dependency management

# Terraform 1.3+ provides:
# - Enhanced for_each functionality
# - Improved state management
# - Better error handling and validation
# - Support for complex variable types
# - Enhanced provider configuration options

# Archive Provider 2.4+ includes:
# - Improved zip file handling
# - Better support for complex directory structures
# - Enhanced file content templating
# - Optimized for Cloud Functions deployment

# Time Provider 0.12+ includes:
# - Better resource timing management
# - Enhanced sleep and wait functionality
# - Improved dependency handling for resource creation delays

# Random Provider 3.6+ includes:
# - Cryptographically secure random generation
# - Enhanced string and number generation
# - Better support for unique identifier creation
# - Improved resource naming capabilities