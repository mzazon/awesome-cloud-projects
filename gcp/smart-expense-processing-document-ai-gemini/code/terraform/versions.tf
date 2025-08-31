# Terraform and Provider Version Requirements
# Smart Expense Processing using Document AI and Gemini

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5.0"

  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Platform Beta provider for newer features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive provider for creating zip files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Local provider for local file operations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Template provider for file templating
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }
}

# Provider configuration for Google Cloud
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all resources that support them
  default_labels = {
    environment    = var.environment
    project        = "smart-expense-processing"
    managed-by     = "terraform"
    recipe-version = "1.1"
    created-by     = "expense-processing-recipe"
  }

  # Enable request batching for better performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }

  # Scopes for API access
  scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/userinfo.email",
  ]
}

# Provider configuration for Google Cloud Beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all resources that support them
  default_labels = {
    environment    = var.environment
    project        = "smart-expense-processing"
    managed-by     = "terraform"
    recipe-version = "1.1"
    created-by     = "expense-processing-recipe"
  }

  # Enable request batching for better performance
  batching {
    enable_batching = true
    send_after      = "10s"
  }

  # Scopes for API access
  scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/userinfo.email",
  ]
}

# Provider configuration for Random resources
provider "random" {
  # No specific configuration needed
}

# Provider configuration for Archive resources
provider "archive" {
  # No specific configuration needed
}

# Provider configuration for Local resources
provider "local" {
  # No specific configuration needed
}

# Provider configuration for Template resources
provider "template" {
  # No specific configuration needed
}

# Backend configuration (optional - uncomment and modify as needed)
# terraform {
#   backend "gcs" {
#     bucket  = "your-terraform-state-bucket"
#     prefix  = "expense-processing"
#   }
# }

# Alternative backend configurations:

# Local backend (default)
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }

# Cloud Storage backend for team collaboration
# terraform {
#   backend "gcs" {
#     bucket                      = "your-terraform-state-bucket"
#     prefix                      = "expense-processing/terraform.tfstate"
#     impersonate_service_account = "terraform@your-project.iam.gserviceaccount.com"
#   }
# }

# Remote backend for Terraform Cloud
# terraform {
#   backend "remote" {
#     organization = "your-organization"
#     workspaces {
#       name = "expense-processing"
#     }
#   }
# }