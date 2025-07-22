# ==============================================================================
# Terraform and Provider Version Constraints
# ==============================================================================
# This file defines the required versions for Terraform and providers
# to ensure compatibility and reproducible deployments.
# ==============================================================================

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.3.0"

  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 5.44.0"
    }

    # Archive provider for creating zip files
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }

    # Random provider for generating unique values
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }

    # Time provider for time-based resources
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12.0"
    }

    # Null provider for provisioners and local execution
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
  }

  # Backend configuration for state management
  # Uncomment and configure as needed for your environment
  /*
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "event-processing/terraform.tfstate"
  }
  */
}

# ==============================================================================
# Provider Configuration
# ==============================================================================

# Configure the Google Cloud Provider
provider "google" {
  # Project and region are specified via variables
  project = var.project_id
  region  = var.region

  # Default labels for all resources (when supported)
  default_labels = merge(var.labels, {
    terraform-managed = "true"
    last-updated     = formatdate("YYYY-MM-DD", timestamp())
  })

  # User project override for API quotas and billing
  user_project_override = true

  # Request timeout for API calls
  request_timeout = "60s"

  # Batch requests for better performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }
}

# Configure the Archive provider
provider "archive" {
  # No specific configuration required
}

# Configure the Random provider  
provider "random" {
  # No specific configuration required
}

# Configure the Time provider
provider "time" {
  # No specific configuration required
}

# Configure the Null provider
provider "null" {
  # No specific configuration required
}

# ==============================================================================
# Provider Feature Configuration
# ==============================================================================

# Data source for Google Cloud project information
data "google_project" "current" {
  project_id = var.project_id
}

# Data source for Google Cloud client configuration
data "google_client_config" "current" {}

# ==============================================================================
# Local Values for Provider Features
# ==============================================================================

locals {
  # Current timestamp for resource naming and tracking
  timestamp = formatdate("YYYY-MM-DD-hhmm", timestamp())
  
  # Project information
  project_number = data.google_project.current.number
  project_name   = data.google_project.current.name
  
  # Provider feature flags
  provider_features = {
    # Enable new Google Cloud features as they become available
    memorystore_unified_api = true
    cloud_functions_v2      = true
    bigquery_v2_api        = true
    pubsub_v2_api          = true
  }
  
  # API versions to use
  api_versions = {
    memorystore    = "v1"
    cloud_functions = "v2"
    bigquery       = "v2"
    pubsub         = "v1"
    monitoring     = "v3"
  }
}

# ==============================================================================
# Version Compatibility Notes
# ==============================================================================

/*
VERSION COMPATIBILITY NOTES:

1. Terraform >= 1.3.0:
   - Required for the new optional() function
   - Enhanced variable validation
   - Improved module composition features

2. Google Provider ~> 5.44.0:
   - Latest stable version with new Memorystore unified API
   - Enhanced Cloud Functions v2 support
   - Improved BigQuery features
   - Better IAM and security controls

3. Archive Provider ~> 2.4.0:
   - Required for creating function source zip files
   - Better compression and file handling

4. Random Provider ~> 3.6.0:
   - Used for generating unique resource names
   - Improved randomization algorithms

5. Time Provider ~> 0.12.0:
   - Used for time-based resource management
   - Better timestamp handling

6. Null Provider ~> 3.2.0:
   - Used for local provisioners and triggers
   - Improved lifecycle management

UPGRADE NOTES:
- Always test upgrades in a development environment first
- Review provider changelogs before upgrading
- Use `terraform plan` to preview changes before applying
- Consider using version pinning for production deployments

BACKWARD COMPATIBILITY:
- This configuration maintains compatibility with Terraform 1.3+
- Google provider versions 5.40+ should work with minimal changes
- Older versions may require syntax adjustments

FEATURE FLAGS:
- New Google Cloud features are enabled through local values
- Disable features if using older provider versions
- Check provider documentation for feature availability

STATE MANAGEMENT:
- Configure remote state backend for production deployments
- Use state locking to prevent concurrent modifications
- Regular state backups recommended for critical environments
*/