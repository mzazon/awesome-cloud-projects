# ===================================
# PROVIDER REQUIREMENTS AND VERSIONS
# ===================================
#
# This file defines the Terraform and provider version requirements
# for the dynamic configuration management solution.

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive Provider for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# ===================================
# AWS PROVIDER CONFIGURATION
# ===================================

# Configure the AWS Provider with default tags
provider "aws" {
  # Provider configuration will use environment variables or AWS CLI profiles
  # for authentication and region selection
  
  default_tags {
    tags = {
      Terraform   = "true"
      Project     = "ConfigManager"
      Repository  = "recipes"
      Recipe      = "dynamic-configuration-management-parameter-store-lambda"
      CreatedBy   = "terraform"
      LastUpdated = timestamp()
    }
  }
}

# ===================================
# PROVIDER VERSIONS AND FEATURES
# ===================================

# AWS Provider version 5.x features used in this configuration:
# - Enhanced support for Lambda layers and environment variables
# - Improved IAM policy validation and error messages  
# - Advanced CloudWatch dashboard configuration options
# - Better EventBridge rule pattern validation
# - Enhanced SSM Parameter Store encryption options
# - Improved resource tagging and default tag support

# Random Provider version 3.x features used:
# - Random ID generation for unique resource naming
# - Improved entropy for resource suffix generation

# Archive Provider version 2.x features used:
# - Template file support for Lambda function code
# - Enhanced zip file creation with better error handling
# - Support for dynamic content generation

# ===================================
# BACKEND CONFIGURATION
# ===================================

# Backend configuration is intentionally not specified here to allow
# flexibility in deployment. Configure backend in one of these ways:
#
# 1. Backend configuration file:
#    Create a backend.tf file or use terraform init -backend-config
#
# 2. Terraform Cloud/Enterprise:
#    Configure remote backend in Terraform Cloud
#
# 3. Local development:
#    Use local backend (default) for development and testing
#
# Example S3 backend configuration (create separate backend.tf file):
# terraform {
#   backend "s3" {
#     bucket         = "your-terraform-state-bucket"
#     key            = "config-manager/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-state-locks"
#   }
# }

# ===================================
# EXPERIMENTAL FEATURES
# ===================================

# This configuration uses stable Terraform features only.
# No experimental features are enabled to ensure compatibility
# across different Terraform versions within the specified range.

# ===================================
# VERSION COMPATIBILITY NOTES
# ===================================

# Terraform Version Compatibility:
# - Minimum version: 1.0.0 (supports required_providers syntax)
# - Tested with: 1.5.x and 1.6.x
# - Maximum tested: 1.7.x

# AWS Provider Version Compatibility:
# - Version 5.x provides the latest AWS service features
# - Maintains backward compatibility with existing configurations
# - Includes enhanced validation and error messages
# - Supports all AWS services used in this configuration

# Random Provider Version Compatibility:
# - Version 3.1.x provides stable random resource generation
# - Maintains state consistency across terraform runs
# - Compatible with Terraform 1.0+

# Archive Provider Version Compatibility:
# - Version 2.2.x provides reliable zip file creation
# - Supports template files and dynamic content
# - Compatible with all specified Terraform versions

# Migration Notes:
# - When upgrading providers, review the CHANGELOG for breaking changes
# - Test in development environment before applying to production
# - Some older provider versions may require state migration
# - Always backup state files before major version upgrades