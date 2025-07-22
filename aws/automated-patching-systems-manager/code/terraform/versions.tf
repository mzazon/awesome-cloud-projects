# Terraform and Provider Version Requirements
# This file specifies the minimum versions for Terraform and providers
# to ensure compatibility and access to required features

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider for all AWS resource management
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project     = "Automated Patching"
      Environment = var.environment
      Recipe      = "automated-patching-maintenance-windows-systems-manager"
      ManagedBy   = "Terraform"
    }
  }
}

# Configure the Random Provider
provider "random" {
  # No configuration needed for random provider
}