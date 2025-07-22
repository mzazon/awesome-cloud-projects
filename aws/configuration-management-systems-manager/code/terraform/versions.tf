# Provider version constraints for AWS Systems Manager State Manager infrastructure
# This file defines the required Terraform and provider versions for consistent deployments

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# AWS provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Systems Manager State Manager"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "configuration-management-systems-manager-state-manager"
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}