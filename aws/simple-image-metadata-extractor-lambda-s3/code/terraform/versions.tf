# ============================================================================
# TERRAFORM VERSION AND PROVIDER REQUIREMENTS
# ============================================================================
# This file defines the minimum Terraform version and required providers
# with their version constraints for the image metadata extraction infrastructure.
# ============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # AWS Provider for main infrastructure resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Archive provider for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive" 
      version = "~> 2.4"
    }
    
    # Local provider for creating local files and executing local commands
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    
    # Null provider for executing provisioners and creating dependencies
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    
    # External provider for running external programs and data sources
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }

  # Terraform Cloud/Enterprise configuration (optional)
  # Uncomment and configure if using Terraform Cloud or Enterprise
  # cloud {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "image-metadata-extractor"
  #   }
  # }

  # Backend configuration for state storage (optional)
  # Configure based on your state storage requirements
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "image-metadata-extractor/terraform.tfstate"
  #   region = "us-east-1"
  #   
  #   # Optional: DynamoDB table for state locking
  #   dynamodb_table = "terraform-state-locks"
  #   encrypt        = true
  # }
}

# ============================================================================
# AWS PROVIDER CONFIGURATION
# ============================================================================

# Configure the AWS Provider with default tags and settings
provider "aws" {
  region = var.aws_region

  # Apply default tags to all resources created by this provider
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "simple-image-metadata-extractor"
      Service     = "ImageProcessing"
      CostCenter  = var.environment == "prod" ? "Production" : "Development"
      Owner       = "DevOps"
      
      # Add compliance and governance tags
      DataClassification = var.data_classification
      BackupRequired    = "true"
      MonitoringEnabled = tostring(var.enable_monitoring)
    }
  }

  # Retry configuration for API calls
  retry_mode     = "adaptive"
  max_retries    = 3

  # Assume role configuration (optional)
  # Uncomment and configure if using cross-account access
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT-ID:role/TerraformRole"
  #   session_name = "TerraformSession"
  #   external_id  = "unique-external-id"
  # }

  # Ignore specific tags that might be applied by AWS services
  ignore_tags {
    key_prefixes = [
      "aws:",
      "cloudformation:",
    ]
  }
}

# ============================================================================
# ADDITIONAL PROVIDER CONFIGURATIONS
# ============================================================================

# Configure the Random provider
provider "random" {}

# Configure the Archive provider
provider "archive" {}

# Configure the Local provider  
provider "local" {}

# Configure the Null provider
provider "null" {}

# Configure the External provider
provider "external" {}

# ============================================================================
# PROVIDER FEATURE FLAGS AND EXPERIMENTAL FEATURES
# ============================================================================

# AWS Provider feature flags (if needed)
# These are typically used for beta or experimental features
# provider "aws" {
#   # Enable S3 bucket replication time control
#   s3_use_path_style = false
#   
#   # Skip region validation for custom endpoints
#   skip_region_validation = false
#   
#   # Skip credentials validation
#   skip_credentials_validation = false
#   
#   # Skip requesting account ID
#   skip_requesting_account_id = false
# }

# ============================================================================
# PROVIDER VERSION CONSTRAINTS EXPLANATION
# ============================================================================

# Version Constraint Explanations:
#
# AWS Provider (~> 5.70):
# - Uses the AWS Provider v5.x series, starting from 5.70
# - Allows automatic updates to patch versions (5.70.x) and minor versions (5.71, 5.72, etc.)
# - Does not allow updates to major versions (6.x) which might contain breaking changes
# - Version 5.70+ includes support for latest Lambda features and improved S3 configurations
#
# Random Provider (~> 3.6):
# - Uses Random Provider v3.x series, starting from 3.6
# - Provides random string, password, and ID generation capabilities
# - Stable API with consistent behavior across versions
#
# Archive Provider (~> 2.4):
# - Uses Archive Provider v2.x series, starting from 2.4
# - Handles ZIP file creation for Lambda deployment packages
# - Supports source code hashing for change detection
#
# Local Provider (~> 2.4):
# - Uses Local Provider v2.x series, starting from 2.4
# - Manages local files and executes local commands
# - Used for creating Lambda function template files
#
# Null Provider (~> 3.2):
# - Uses Null Provider v3.x series, starting from 3.2
# - Provides null_resource for running provisioners
# - Used for creating Lambda layers and executing setup scripts
#
# External Provider (~> 2.3):
# - Uses External Provider v2.x series, starting from 2.3
# - Executes external programs and processes their output
# - Used for dynamic data retrieval and external integrations

# ============================================================================
# MINIMUM TERRAFORM VERSION EXPLANATION
# ============================================================================

# Terraform Version (>= 1.6.0):
# - Requires Terraform 1.6.0 or later for modern features and security improvements
# - Supports enhanced validation rules and type constraints
# - Includes improved provider dependency resolution
# - Provides better error messages and debugging capabilities
# - Supports modern HCL syntax and functions
#
# Key features used that require 1.6.0+:
# - Enhanced variable validation with custom error messages
# - Improved dynamic blocks with for_each expressions
# - Advanced conditional expressions and type constraints
# - Better handling of provider configurations and aliases
# - Improved state management and backend configurations

# ============================================================================
# COMPATIBILITY NOTES
# ============================================================================

# AWS Region Compatibility:
# - This configuration is tested and compatible with all AWS regions
# - Some newer features may not be available in all regions immediately
# - GovCloud and China regions may have different provider requirements
#
# Provider Compatibility Matrix:
# - AWS Provider 5.70+ is compatible with Terraform 1.6.0+
# - All other providers are compatible with specified Terraform version
# - No known conflicts between provider versions specified
#
# Operating System Compatibility:
# - Terraform and providers support Windows, macOS, and Linux
# - Shell scripts in null_resource provisioners are bash-compatible
# - Docker commands require Docker to be installed for layer building