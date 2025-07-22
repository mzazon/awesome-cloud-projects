# =============================================================================
# Terraform and Provider Version Constraints
# Edge-to-Cloud Video Analytics with Media CDN and Vertex AI
# =============================================================================

# Terraform version constraint
terraform {
  required_version = ">= 1.0"
  
  # Provider requirements with version constraints
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    
    # Google Cloud Platform Beta provider (for preview features)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    
    # Archive provider for creating function source archives
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
    
    # Time provider for resource delays and time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    
    # Template provider for templating configuration files
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }
  
  # Backend configuration (uncomment and configure for remote state)
  # backend "gcs" {
  #   bucket  = "your-terraform-state-bucket"
  #   prefix  = "video-analytics/terraform.tfstate"
  # }
  
  # Enable provider features
  experiments = []
}

# =============================================================================
# Provider Configuration
# =============================================================================

# Primary Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Default labels applied to all resources
  default_labels = {
    environment        = var.environment
    managed-by        = "terraform"
    project           = "video-analytics"
    terraform-version = "1.0+"
    provider-version  = "6.0+"
  }
  
  # Request timeout for API calls
  request_timeout = "60s"
  
  # Add user project override for billing
  user_project_override = true
  
  # Enable request reason for audit logging
  add_terraform_attribution_label = true
}

# Google Cloud Beta provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Default labels for beta resources
  default_labels = {
    environment        = var.environment
    managed-by        = "terraform"
    project           = "video-analytics"
    terraform-version = "1.0+"
    provider-version  = "6.0+"
    preview-features  = "enabled"
  }
  
  request_timeout = "60s"
  user_project_override = true
  add_terraform_attribution_label = true
}

# Random provider configuration
provider "random" {
  # No specific configuration required
}

# Archive provider configuration
provider "archive" {
  # No specific configuration required
}

# Time provider configuration
provider "time" {
  # No specific configuration required
}

# Template provider configuration (deprecated but still used for legacy templates)
provider "template" {
  # No specific configuration required
}

# =============================================================================
# Data Sources for Provider Information
# =============================================================================

# Get current Google Cloud project information
data "google_project" "current" {
  project_id = var.project_id
}

# Get current client configuration
data "google_client_config" "current" {}

# Get available Google Cloud regions
data "google_compute_regions" "available" {}

# Get available Google Cloud zones in the selected region
data "google_compute_zones" "available" {
  region = var.region
}

# =============================================================================
# Provider Feature Validation
# =============================================================================

# Validate that required APIs are available in the project
data "google_project_service" "required_services" {
  for_each = toset([
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "aiplatform.googleapis.com",
    "videointelligence.googleapis.com",
    "eventarc.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com",
    "networkconnectivity.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
}

# =============================================================================
# Version Compatibility Notes
# =============================================================================

/*
Provider Version Compatibility:

Google Provider (v6.0+):
- Supports latest Cloud Functions 2nd generation
- Includes Vertex AI resource management
- Media CDN (Cloud CDN) configuration
- Enhanced IAM and security features
- Improved Cloud Storage lifecycle policies

Google Beta Provider (v6.0+):
- Preview features for Vertex AI
- Advanced Cloud Functions configurations
- Experimental networking features

Terraform Version (1.0+):
- Module composition and dependency management
- Improved state management
- Enhanced error handling
- Support for provider versioning

Feature Requirements:
- Vertex AI: Requires google provider >= 5.0
- Cloud Functions 2nd gen: Requires google provider >= 4.50
- Media CDN: Requires google provider >= 4.40
- Eventarc triggers: Requires google provider >= 4.20

Minimum Supported Versions:
- Terraform: 1.0.0
- Google Provider: 6.0.0
- Google Beta Provider: 6.0.0
- Random Provider: 3.1.0
- Archive Provider: 2.2.0

Recommended Versions:
- Terraform: Latest stable (1.6+)
- Google Provider: Latest stable (6.x)
- Google Beta Provider: Latest stable (6.x)

Breaking Changes to Monitor:
- Google provider v5.x -> v6.x: Resource naming conventions
- Cloud Functions v1 -> v2: Different resource types
- Vertex AI: API changes in newer versions
- Media CDN: Configuration syntax updates

Migration Notes:
- When upgrading from v5.x to v6.x, review resource configurations
- Test deployments in non-production environments first
- Consider using terraform plan with -refresh=false for large infrastructures
- Review provider documentation for deprecated resources

Deprecated Features:
- google_cloudfunctions_function (v1) - Use google_cloudfunctions2_function
- Legacy Cloud CDN configuration - Use new Media CDN resources
- Old Vertex AI APIs - Use current aiplatform.googleapis.com

Security Considerations:
- Always use specific version constraints in production
- Review provider changelogs for security updates
- Test provider upgrades in development environments
- Monitor for deprecated authentication methods
*/