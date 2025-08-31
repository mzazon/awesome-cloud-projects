# =============================================================================
# Simple Application Configuration with AppConfig and Lambda - Versions
# 
# This file defines the required providers and their version constraints
# for the Terraform configuration.
# =============================================================================

terraform {
  # Specify minimum Terraform version
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider - Primary provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider - Used for generating unique resource suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive Provider - Used for packaging Lambda function code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  # AWS region will be set via AWS_REGION environment variable
  # or AWS CLI/SDK configuration

  # Default tags applied to all resources
  default_tags {
    tags = {
      ManagedBy     = "Terraform"
      Project       = "Simple AppConfig Demo"
      Recipe        = "simple-app-configuration-appconfig-lambda"
      Repository    = "cloud-recipes"
      CreatedBy     = "terraform"
      Environment   = var.environment
    }
  }
}

# Configure the Random Provider
provider "random" {
  # No additional configuration required
}

# Configure the Archive Provider  
provider "archive" {
  # No additional configuration required
}