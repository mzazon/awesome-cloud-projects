# Terraform provider version constraints
# This file defines the required Terraform version and provider versions
# for the CodeArtifact artifact management infrastructure

terraform {
  # Minimum required Terraform version
  required_version = ">= 1.5"

  required_providers {
    # AWS provider for creating CodeArtifact and IAM resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# AWS Provider configuration
# Region will be determined by AWS CLI configuration or environment variables
provider "aws" {
  # Additional provider configuration can be added here if needed
  # For example, default tags that apply to all resources
  default_tags {
    tags = {
      Project     = "artifact-management-codeartifact"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Random provider configuration
provider "random" {
  # No specific configuration needed for the random provider
}