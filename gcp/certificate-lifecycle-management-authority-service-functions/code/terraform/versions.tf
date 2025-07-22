# ==============================================================================
# Certificate Lifecycle Management with Certificate Authority Service and Cloud Functions
# Provider Version Requirements and Configuration
# ==============================================================================

terraform {
  required_version = ">= 1.6"
  
  required_providers {
    # Google Cloud Provider - primary provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44"
    }
    
    # Google Cloud Beta Provider - for beta features if needed
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44"
    }
    
    # Random Provider - for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Archive Provider - for creating ZIP files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Time Provider - for time-based operations if needed
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
  
  # Optional: Configure backend for state management
  # Uncomment and configure for production deployments
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "certificate-lifecycle-management"
  # }
}

# ==============================================================================
# Google Cloud Provider Configuration
# ==============================================================================

# Primary Google Cloud provider configuration
provider "google" {
  # Project ID will be provided via variable or default project
  project = var.project_id != "" ? var.project_id : null
  region  = var.region
  
  # Enable the following APIs automatically
  # This list includes all services used in this configuration
  default_labels = {
    terraform   = "true"
    solution    = "certificate-lifecycle-management"
    environment = var.environment
  }
  
  # Request/response logging for debugging (disable in production)
  # request_reason  = "terraform-deployment"
  # request_timeout = "60s"
}

# Google Cloud Beta provider for beta features
provider "google-beta" {
  project = var.project_id != "" ? var.project_id : null
  region  = var.region
  
  default_labels = {
    terraform   = "true"
    solution    = "certificate-lifecycle-management"
    environment = var.environment
  }
}

# Random provider configuration
provider "random" {
  # No special configuration needed
}

# Archive provider configuration
provider "archive" {
  # No special configuration needed
}

# Time provider configuration
provider "time" {
  # No special configuration needed
}

# ==============================================================================
# Required Google Cloud APIs
# ==============================================================================

# Note: These APIs should be enabled before running Terraform
# You can enable them manually or use the google_project_service resource

# Enable Certificate Authority Service API
resource "google_project_service" "privateca_api" {
  service                    = "privateca.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Cloud Functions API
resource "google_project_service" "cloudfunctions_api" {
  service                    = "cloudfunctions.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Cloud Build API (required for Cloud Functions)
resource "google_project_service" "cloudbuild_api" {
  service                    = "cloudbuild.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Cloud Scheduler API
resource "google_project_service" "cloudscheduler_api" {
  service                    = "cloudscheduler.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Secret Manager API
resource "google_project_service" "secretmanager_api" {
  service                    = "secretmanager.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Cloud Resource Manager API
resource "google_project_service" "cloudresourcemanager_api" {
  service                    = "cloudresourcemanager.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable IAM API
resource "google_project_service" "iam_api" {
  service                    = "iam.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Cloud Logging API
resource "google_project_service" "logging_api" {
  service                    = "logging.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Cloud Monitoring API
resource "google_project_service" "monitoring_api" {
  service                    = "monitoring.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Cloud Storage API
resource "google_project_service" "storage_api" {
  service                    = "storage.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Artifact Registry API (for container images if needed)
resource "google_project_service" "artifactregistry_api" {
  service                    = "artifactregistry.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Cloud Run Admin API (Cloud Functions v2 uses Cloud Run)
resource "google_project_service" "run_api" {
  service                    = "run.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Pub/Sub API (used by Cloud Functions for event triggers)
resource "google_project_service" "pubsub_api" {
  service                    = "pubsub.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# ==============================================================================
# Provider Feature Flags and Experimental Features
# ==============================================================================

# Configure provider-specific features
locals {
  # Features that might be useful for this deployment
  provider_features = {
    # Enable automatic retries for API calls
    enable_automatic_retries = true
    
    # Enable request/response logging for debugging
    enable_request_logging = false
    
    # Maximum number of retries for API calls
    max_retries = 3
    
    # Default timeout for API calls
    request_timeout = "60s"
  }
}

# ==============================================================================
# Version Constraints Explanation
# ==============================================================================

/*
  Version Constraints Rationale:
  
  1. Terraform >= 1.6: 
     - Required for stable provider configuration and modern HCL features
     - Includes improved error handling and state management
  
  2. Google Provider ~> 6.44:
     - Latest stable version with Certificate Authority Service support
     - Includes Cloud Functions v2 and latest security features
     - Pin to minor version to ensure compatibility
  
  3. Google Beta Provider ~> 6.44:
     - Matches main provider version for consistency
     - May be needed for beta features in future enhancements
  
  4. Random Provider ~> 3.6:
     - Stable version for generating unique identifiers
     - Required for creating unique resource names
  
  5. Archive Provider ~> 2.4:
     - Stable version for creating ZIP archives
     - Required for packaging Cloud Function source code
  
  6. Time Provider ~> 0.12:
     - Latest stable version for time-based operations
     - May be used for certificate validity calculations
*/

# ==============================================================================
# Provider Configuration Validation
# ==============================================================================

# Check that required provider features are available
check "provider_versions" {
  assert {
    condition = can(regex("^6\\.", data.google_client_config.current.version))
    error_message = "Google Cloud provider version 6.x is required for this configuration."
  }
}

# Verify project access
check "project_access" {
  assert {
    condition     = data.google_project.current.project_id != ""
    error_message = "Unable to access Google Cloud project. Check authentication and project permissions."
  }
}

# ==============================================================================
# Terraform Configuration Best Practices
# ==============================================================================

/*
  Best Practices Applied:
  
  1. Provider Version Pinning:
     - Use pessimistic version constraints (~>) to allow patch updates
     - Pin to specific minor versions for production stability
  
  2. Required APIs:
     - Explicitly enable all required Google Cloud APIs
     - Use disable_on_destroy = false to prevent service disruption
  
  3. Error Handling:
     - Include validation checks for provider configuration
     - Use meaningful error messages for troubleshooting
  
  4. Documentation:
     - Comprehensive comments explaining version choices
     - Clear explanation of required APIs and their purposes
  
  5. Future Compatibility:
     - Include beta provider for potential future features
     - Structure allows easy addition of new providers
*/