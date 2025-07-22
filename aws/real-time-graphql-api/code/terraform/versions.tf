# ==============================================================================
# Terraform and Provider Version Requirements
# ==============================================================================
# This file specifies the required versions for Terraform and providers used
# in this configuration. Version constraints ensure compatibility and 
# reproducible deployments.
# ==============================================================================

terraform {
  # Terraform version requirement
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating unique suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# ==============================================================================
# Provider Configuration
# ==============================================================================

# AWS Provider configuration
provider "aws" {
  # Default tags applied to all resources
  default_tags {
    tags = {
      ManagedBy           = "Terraform"
      Project             = "GraphQL Blog API"
      Repository          = "recipes/aws/graphql-apis-with-aws-appsync"
      TerraformVersion    = "~> 1.0"
      AWSProviderVersion  = "~> 5.0"
      LastModified        = timestamp()
    }
  }
}

# Random provider configuration
provider "random" {
  # No additional configuration needed for random provider
}