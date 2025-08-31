# Terraform version and provider configuration
# This file defines the required Terraform and provider versions for the
# Simple Color Palette Generator infrastructure deployment

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# AWS Provider configuration
# Inherits region and credentials from environment variables or AWS CLI configuration
provider "aws" {
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "simple-color-palette-generator-lambda-s3"
    }
  }
}