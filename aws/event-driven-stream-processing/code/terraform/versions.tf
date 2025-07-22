# Terraform and Provider Version Constraints
# This file defines the minimum required versions for Terraform and providers
# to ensure compatibility and consistent behavior across deployments.

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# AWS Provider Configuration
# Configure the AWS provider with default tags for resource management
provider "aws" {
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "real-time-data-processing-with-kinesis-lambda"
    }
  }
}