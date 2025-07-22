# ==============================================================================
# TERRAFORM VERSION AND PROVIDER REQUIREMENTS
# ==============================================================================
# This file defines the minimum Terraform version and required provider versions
# for the network performance optimization solution, ensuring compatibility and
# access to the latest features for Google Cloud Platform services.
# ==============================================================================

terraform {
  # Specify minimum Terraform version for advanced features and stability
  required_version = ">= 1.0"

  # Required providers with version constraints for stability and feature access
  required_providers {
    # Google Cloud Platform provider for core GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Platform Beta provider for preview features and advanced configurations
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive provider for creating function source code packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Template provider for dynamic configuration generation
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }

    # Time provider for time-based resource management
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# ==============================================================================
# GOOGLE CLOUD PROVIDER CONFIGURATION
# ==============================================================================

# Primary Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = "${var.region}-a"

  # Enable user project override for billing configuration
  user_project_override = true
  
  # Set billing project for API requests
  billing_project = var.project_id

  # Request timeout configuration for large resource operations
  request_timeout = "60s"

  # Retry configuration for resilient deployments
  request_reason = "terraform-network-optimization"
}

# Google Cloud Beta provider for accessing preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = "${var.region}-a"

  user_project_override = true
  billing_project       = var.project_id
  request_timeout       = "60s"
}

# ==============================================================================
# RANDOM PROVIDER CONFIGURATION
# ==============================================================================

# Random provider for generating unique identifiers
provider "random" {
  # No specific configuration required
}

# ==============================================================================
# ARCHIVE PROVIDER CONFIGURATION
# ==============================================================================

# Archive provider for creating function deployment packages
provider "archive" {
  # No specific configuration required
}

# ==============================================================================
# TEMPLATE PROVIDER CONFIGURATION
# ==============================================================================

# Template provider for dynamic file generation
provider "template" {
  # No specific configuration required
}

# ==============================================================================
# TIME PROVIDER CONFIGURATION
# ==============================================================================

# Time provider for timestamp-based operations
provider "time" {
  # No specific configuration required
}

# ==============================================================================
# BACKEND CONFIGURATION (OPTIONAL)
# ==============================================================================
# Uncomment and configure the backend block below to store Terraform state
# in Google Cloud Storage for team collaboration and state locking.

/*
terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "network-optimization/terraform.tfstate"
    
    # Optional: Enable state locking with Cloud Storage
    encryption_key = "your-encryption-key"  # Optional customer-managed encryption
  }
}
*/

# ==============================================================================
# PROVIDER FEATURE FLAGS AND CONFIGURATION
# ==============================================================================

# Configure default labels that will be applied to all Google Cloud resources
locals {
  default_labels = {
    managed_by          = "terraform"
    solution           = "network-optimization"
    environment        = var.environment
    deployment_version = "1.0"
    created_date       = formatdate("YYYY-MM-DD", timestamp())
  }
}

# ==============================================================================
# VERSION COMPATIBILITY NOTES
# ==============================================================================
/*
Version Compatibility Matrix:
- Terraform: >= 1.0 (Required for advanced for_each and validation features)
- google provider: ~> 6.0 (Latest stable with Network Intelligence Center support)
- google-beta provider: ~> 6.0 (For preview network optimization features)
- random provider: ~> 3.1 (For secure random ID generation)
- archive provider: ~> 2.4 (For Cloud Function packaging)

Key Features Enabled by These Versions:
- Network Connectivity Center (google provider 6.0+)
- Network Management Connectivity Tests (google provider 5.0+)
- Cloud Functions Gen2 (google provider 4.40+)
- Advanced VPC Flow Logs configuration (google provider 4.0+)
- Enhanced Pub/Sub features (google provider 5.0+)
- Improved Cloud Monitoring integration (google provider 5.20+)

Breaking Changes to be Aware of:
- google provider 5.0: Terraform block required_providers is mandatory
- google provider 6.0: Some resource attributes renamed for consistency
- Cloud Functions: Gen1 to Gen2 migration may require resource recreation

Upgrade Path:
1. Ensure Terraform >= 1.0 is installed
2. Update provider versions gradually (5.x -> 6.x)
3. Test in non-production environment first
4. Review provider changelogs for breaking changes
5. Update resource configurations as needed

Security Considerations:
- Always use specific version constraints (~> instead of >=)
- Regularly update to latest patch versions for security fixes
- Review provider security advisories before upgrading
- Use terraform plan before applying changes in production
*/