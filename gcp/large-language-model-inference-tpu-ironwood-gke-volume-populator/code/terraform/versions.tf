# ================================================================
# Provider and Version Requirements
# 
# This file defines the required providers and their version
# constraints for the TPU Ironwood LLM inference infrastructure.
# All provider versions are pinned to ensure reproducible deployments.
# ================================================================

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.9.0"
  
  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44.0"
    }
    
    # Google Cloud Platform Beta provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    
    # Kubernetes provider for managing K8s resources (optional)
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35.0"
    }
  }
}

# ================================================================
# Google Cloud Provider Configuration
# ================================================================
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Default labels applied to all resources
  default_labels = {
    terraform   = "true"
    environment = var.environment
    recipe      = "tpu-ironwood-inference"
  }
  
  # Enable user project override for better API quota management
  user_project_override = true
  
  # Request timeout for long-running operations
  request_timeout = "5m"
}

# ================================================================
# Google Cloud Beta Provider Configuration
# ================================================================
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  
  # Default labels applied to all beta resources
  default_labels = {
    terraform   = "true"
    environment = var.environment
    recipe      = "tpu-ironwood-inference"
    provider    = "google-beta"
  }
  
  # Enable user project override for better API quota management
  user_project_override = true
  
  # Request timeout for long-running operations
  request_timeout = "10m"
}

# ================================================================
# Random Provider Configuration
# ================================================================
provider "random" {
  # No specific configuration required for random provider
}

# ================================================================
# Kubernetes Provider Configuration
# ================================================================
# Note: This provider is configured to use GKE cluster credentials
# It will be dynamically configured after the cluster is created
provider "kubernetes" {
  # Configuration will be provided through environment variables or
  # kubectl config after cluster creation
  
  # Uncomment the following block if you want to configure K8s provider
  # to automatically connect to the created GKE cluster:
  
  # host                   = "https://${google_container_cluster.tpu_cluster.endpoint}"
  # token                  = data.google_client_config.default.access_token
  # cluster_ca_certificate = base64decode(google_container_cluster.tpu_cluster.master_auth.0.cluster_ca_certificate)
}

# ================================================================
# Data Sources for Provider Configuration
# ================================================================

# Get current Google Cloud client configuration
data "google_client_config" "default" {}

# Get current Google Cloud project information
data "google_project" "current" {
  project_id = var.project_id
}

# ================================================================
# Provider Feature Flags and Experimental Features
# ================================================================

# Configure Google provider to use new resource lifecycle management
# This ensures better handling of resource dependencies and updates
provider "google" {
  alias = "resource_manager"
  
  # Enhanced resource management features
  batching {
    enable_batching = true
    send_after      = "5s"
  }
}

# ================================================================
# Backend Configuration Recommendations
# ================================================================

# Uncomment and configure the following backend if you want to store
# Terraform state in Google Cloud Storage for team collaboration:

# terraform {
#   backend "gcs" {
#     bucket = "your-terraform-state-bucket"
#     prefix = "terraform/state/tpu-ironwood-inference"
#   }
# }

# ================================================================
# Version Compatibility Notes
# ================================================================

# Google Provider v6.44.0+ Features Used:
# - Enhanced GKE cluster management
# - Parallelstore instance support
# - Workload Identity v2 configuration
# - Improved Cloud Monitoring dashboard management
# - Updated IAM binding formats

# Terraform v1.9.0+ Features Used:
# - Enhanced validation functions
# - Improved error handling
# - Better provider dependency management
# - Advanced variable validation
# - Optional object attributes

# Known Compatibility Issues:
# - TPU Ironwood requires Google Cloud Provider v6.40.0+
# - Parallelstore support requires Google Cloud Provider v6.35.0+
# - Some TPU features may require google-beta provider
# - Workload Identity v2 requires Kubernetes provider v2.30.0+

# ================================================================
# Upgrade Path and Migration Notes
# ================================================================

# When upgrading provider versions:
# 1. Review the provider changelog for breaking changes
# 2. Test in a development environment first
# 3. Update version constraints gradually
# 4. Verify TPU and Parallelstore compatibility
# 5. Check for deprecated resource attributes

# Migration from older versions:
# - Provider versions < 6.0.0 may require resource recreation
# - TPU resource names may change between major versions
# - IAM binding formats have been updated
# - Monitoring dashboard JSON schema may require updates