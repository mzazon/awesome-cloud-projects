# ==============================================================================
# Terraform and Provider Version Requirements
# ==============================================================================
# This file defines the minimum versions of Terraform and AWS provider required
# for this configuration to work correctly with all features and resources.

terraform {
  # Require minimum Terraform version for stability and feature support
  required_version = ">= 1.6"

  # Required providers with version constraints
  required_providers {
    # AWS Provider for all AWS resources (Route 53, CloudWatch, SNS)
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Optional: Configure Terraform Cloud or S3 backend for state management
  # Uncomment and modify as needed for your environment
  #
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "website-uptime-monitoring/terraform.tfstate"
  #   region = "us-east-1"
  #   
  #   # Enable state locking and consistency checking
  #   dynamodb_table = "terraform-state-locks"
  #   encrypt        = true
  # }
  #
  # backend "remote" {
  #   organization = "your-terraform-cloud-org"
  #   
  #   workspaces {
  #     name = "website-uptime-monitoring"
  #   }
  # }
}

# ==============================================================================
# AWS Provider Configuration
# ==============================================================================
# Configure the AWS provider with appropriate settings for Route 53 health checks
# and CloudWatch monitoring

provider "aws" {
  # Default region for resources
  # Note: Route 53 health check metrics are only available in us-east-1
  region = "us-east-1"

  # Default tags applied to all resources created by this provider
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = "website-uptime-monitoring"
      Environment = "production"
      Repository  = "recipes/aws/website-uptime-monitoring-route-53-health-checks"
    }
  }

  # Optional: Configure provider-level retry and timeout settings
  retry_mode      = "adaptive"
  max_retries     = 3
  
  # Skip credential validation for faster plan/apply in CI/CD
  # skip_credentials_validation = true
  # skip_metadata_api_check     = true
  # skip_region_validation      = true
}

# ==============================================================================
# Provider Feature Flags and Experimental Features
# ==============================================================================
# Configure any experimental or preview features needed for this configuration

# Note: AWS Provider v6.x includes the following key features used in this configuration:
# - Enhanced Route 53 health check support with regional configuration
# - Improved CloudWatch alarm metric query support
# - Updated SNS topic policy management
# - Better tagging support across all resources

# ==============================================================================
# Version Compatibility Notes
# ==============================================================================
# This configuration is compatible with:
# - Terraform >= 1.6 (for improved validation and lifecycle management)
# - AWS Provider >= 6.0 (for latest Route 53 and CloudWatch features)
# - Random Provider >= 3.1 (for consistent random string generation)
#
# Breaking changes from previous versions:
# - AWS Provider v6.x: Some resource attributes may have changed
# - AWS Provider v5.x to v6.x: Review migration guide for any deprecated features
#
# Recommended versions for production use:
# - Terraform: Latest stable (1.6.x or higher)
# - AWS Provider: Latest stable (6.x series)
# - Random Provider: Latest stable (3.x series)