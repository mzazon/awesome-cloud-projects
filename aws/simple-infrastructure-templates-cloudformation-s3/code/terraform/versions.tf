# Terraform and Provider Version Requirements
# This file defines the minimum Terraform version and required providers
# for the Simple Infrastructure Templates with CloudFormation and S3 recipe

terraform {
  # Require minimum Terraform version for stable feature support
  required_version = ">= 1.6"

  # Define required providers with version constraints
  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use latest 5.x version for current features
    }
    
    # Random provider for generating unique identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  # Provider configuration will use:
  # - AWS CLI profile or environment variables for credentials
  # - AWS_REGION environment variable or default region
  # - Assumes proper AWS credentials are configured locally
  
  # Enable provider-level default tags for all resources
  default_tags {
    tags = {
      Project     = "Simple-Infrastructure-Templates"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Recipe      = "simple-infrastructure-templates-cloudformation-s3"
    }
  }
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required for random provider
  # Used for generating unique bucket names and suffixes
}