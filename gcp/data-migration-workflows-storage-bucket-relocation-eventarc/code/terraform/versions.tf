# Terraform version and provider requirements for GCP Data Migration Workflows

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5.0"
  
  # Required providers and their versions
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
      version = "~> 3.6"
    }
    
    # Time provider for time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    
    # Archive provider for creating zip files
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Local provider for local file operations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
  
  # Optional: Configure remote state backend
  # Uncomment and configure as needed for your environment
  
  # backend "gcs" {
  #   bucket  = "your-terraform-state-bucket"
  #   prefix  = "terraform/data-migration-workflows"
  # }
  
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "terraform/data-migration-workflows/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# Configure the Google Cloud Provider
provider "google" {
  # Project and region will be set via variables
  # Authentication can be set via:
  # - GOOGLE_APPLICATION_CREDENTIALS environment variable
  # - gcloud auth application-default login
  # - Service account key file
  
  # Optional: Set default labels for all resources
  default_labels = {
    terraform   = "true"
    environment = var.environment
    project     = "data-migration-workflows"
  }
  
  # Optional: Configure user project override for billing
  user_project_override = true
  
  # Optional: Configure billing project
  billing_project = var.project_id
}

# Configure the Google Cloud Beta Provider (for preview features)
provider "google-beta" {
  # Same configuration as the main provider
  default_labels = {
    terraform   = "true"
    environment = var.environment
    project     = "data-migration-workflows"
  }
  
  user_project_override = true
  billing_project       = var.project_id
}

# Configure the Random provider
provider "random" {
  # No specific configuration needed
}

# Configure the Time provider
provider "time" {
  # No specific configuration needed
}

# Configure the Archive provider
provider "archive" {
  # No specific configuration needed
}

# Configure the Local provider
provider "local" {
  # No specific configuration needed
}

# Provider feature flags and experimental features
# These are commented out by default but can be enabled if needed

# Enable provider features
# provider "google" {
#   # Enable new resource behavior
#   # Note: These features may be subject to change
#   
#   # Enable billing budget notifications
#   enable_billing_budget_notifications = true
#   
#   # Enable resource manager tags
#   enable_resource_manager_tags = true
#   
#   # Enable compute engine features
#   enable_compute_engine_features = true
# }

# Version constraints explanation:
# - terraform: ">= 1.5.0" - Requires Terraform 1.5.0 or later for modern features
# - google: "~> 6.0" - Allows any 6.x version, provides latest stable features
# - google-beta: "~> 6.0" - Matches main provider for consistency
# - random: "~> 3.6" - Stable version for random resource generation
# - time: "~> 0.12" - Latest stable version for time-based operations
# - archive: "~> 2.4" - Stable version for archive operations
# - local: "~> 2.5" - Latest stable version for local file operations

# Notes for upgrading providers:
# 1. Always test provider upgrades in a non-production environment first
# 2. Review the provider changelog for breaking changes
# 3. Update version constraints gradually (e.g., 5.x -> 6.x)
# 4. Consider using exact version constraints for production environments
# 5. Use terraform providers lock to maintain consistent versions across team

# Example of exact version constraints for production:
# google = {
#   source  = "hashicorp/google"
#   version = "= 6.44.0"
# }

# Deprecated providers that are no longer needed:
# - google-beta features are now available in the main google provider
# - hashicorp/template is deprecated in favor of templatefile() function
# - hashicorp/null is rarely needed with modern Terraform features