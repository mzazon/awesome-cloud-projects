# =============================================================================
# Provider and Version Requirements for Random Quote API Infrastructure
# =============================================================================
# This file defines the required Terraform version and provider versions
# to ensure consistent deployments across different environments and users.
# Provider versions are pinned to ensure stability and reproducibility.

# -----------------------------------------------------------------------------
# Terraform Version Requirements
# -----------------------------------------------------------------------------
terraform {
  # Minimum Terraform version required for this configuration
  # Version 1.5.0 introduces enhanced state management and provider features
  required_version = ">= 1.5.0"
  
  # Required providers with version constraints
  required_providers {
    # Google Cloud Provider
    # Provides resources for Google Cloud Platform services
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"  # Allow minor updates within major version 5
    }
    
    # Google Cloud Beta Provider
    # Provides access to beta/preview features and resources
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"  # Keep in sync with main Google provider
    }
    
    # Random Provider
    # Used for generating random values for unique resource naming
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Archive Provider
    # Used for creating ZIP archives of Cloud Function source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Local Provider
    # Used for creating local files and executing local commands
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    
    # Null Provider
    # Used for provisioners and resource triggers
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    
    # Time Provider
    # Used for time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
  
  # Optional: Configure remote state backend
  # Uncomment and configure for team collaboration or production environments
  #
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "random-quote-api/terraform.tfstate"
  # }
  #
  # Alternative backend options:
  #
  # backend "remote" {
  #   organization = "your-org"
  #   workspaces {
  #     name = "random-quote-api"
  #   }
  # }
  #
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "random-quote-api/terraform.tfstate"
  #   region = "us-central1"
  # }
}

# -----------------------------------------------------------------------------
# Google Cloud Provider Configuration
# -----------------------------------------------------------------------------
# Configure the main Google Cloud provider with default settings
provider "google" {
  # Project ID is set via variable to allow flexibility across environments
  project = var.project_id
  
  # Default region for resources that don't specify a region
  region = var.region
  
  # Default zone for zonal resources (optional)
  # zone = "${var.region}-a"
  
  # Optional: Specify credentials file path
  # credentials = file("path/to/service-account-key.json")
  
  # Optional: Request timeout for API calls
  request_timeout = "60s"
  
  # Optional: Enable request logging for debugging
  # request_reason = "Terraform deployment for Random Quote API"
  
  # User project override for billing (useful for shared VPC setups)
  user_project_override = true
  
  # Billing project for API calls (if different from main project)
  # billing_project = var.billing_project_id
}

# -----------------------------------------------------------------------------
# Google Cloud Beta Provider Configuration
# -----------------------------------------------------------------------------
# Configure the Google Cloud Beta provider for preview features
provider "google-beta" {
  # Project ID is set via variable to allow flexibility across environments
  project = var.project_id
  
  # Default region for beta resources
  region = var.region
  
  # Keep settings consistent with main provider
  request_timeout = "60s"
  user_project_override = true
}

# -----------------------------------------------------------------------------
# Random Provider Configuration
# -----------------------------------------------------------------------------
# Configure the Random provider (no specific configuration needed)
provider "random" {
  # No configuration required - provider uses system entropy
}

# -----------------------------------------------------------------------------
# Archive Provider Configuration
# -----------------------------------------------------------------------------
# Configure the Archive provider (no specific configuration needed)
provider "archive" {
  # No configuration required
}

# -----------------------------------------------------------------------------
# Local Provider Configuration
# -----------------------------------------------------------------------------
# Configure the Local provider (no specific configuration needed)
provider "local" {
  # No configuration required
}

# -----------------------------------------------------------------------------
# Null Provider Configuration
# -----------------------------------------------------------------------------
# Configure the Null provider (no specific configuration needed)
provider "null" {
  # No configuration required
}

# -----------------------------------------------------------------------------
# Time Provider Configuration
# -----------------------------------------------------------------------------
# Configure the Time provider (no specific configuration needed)
provider "time" {
  # No configuration required
}

# -----------------------------------------------------------------------------
# Provider Feature Flags and Experimental Features
# -----------------------------------------------------------------------------
# Google provider supports various feature flags for experimental functionality
# Uncomment and configure as needed for specific use cases
#
# provider "google" {
#   # ... other configurations ...
#   
#   # Add beta features to stable provider
#   add_terraform_attribution_label = true
#   
#   # Enable specific alpha/beta features
#   enable_alpha_features = false
#   
#   # Custom retry configuration
#   retry_transport {
#     max_retry_delay    = "30s"
#     retry_delay_multiplier = 1.3
#   }
# }

# -----------------------------------------------------------------------------
# Provider Version Compatibility Notes
# -----------------------------------------------------------------------------
# Version compatibility information and upgrade guidance:
#
# Google Provider v5.x:
# - Major changes from v4.x include resource naming updates
# - Enhanced support for Firestore and Cloud Functions Gen 2
# - Improved error handling and retry logic
# - New resources for advanced GCP features
#
# Breaking Changes from v4.x to v5.x:
# - Some resource names have changed (check provider documentation)
# - Default values for certain resources may have changed
# - Enhanced validation for resource configurations
#
# Upgrade Path:
# 1. Review the provider changelog for breaking changes
# 2. Test with a copy of your state in a development environment
# 3. Update resource configurations as needed
# 4. Run terraform plan to verify changes before applying
#
# For production environments, consider pinning to a specific version:
# version = "= 5.11.0"  # Pin to exact version for maximum stability

# -----------------------------------------------------------------------------
# Required Provider Features
# -----------------------------------------------------------------------------
# This configuration requires the following provider features:
#
# Google Provider:
# - Cloud Functions v1 API support
# - Firestore database management
# - Cloud Storage bucket and object management
# - IAM policy management
# - Project service management
#
# Google Beta Provider:
# - Access to preview features (if used)
# - Enhanced resource configurations
#
# Random Provider:
# - Random ID and string generation
# - Entropy-based random values
#
# Archive Provider:
# - ZIP file creation and management
# - File compression utilities
#
# Local Provider:
# - Local file creation and management
# - Local command execution
#
# Null Provider:
# - Resource dependencies and triggers
# - Provisioner support
#
# Time Provider:
# - Time-based resource management
# - Delay and timing controls