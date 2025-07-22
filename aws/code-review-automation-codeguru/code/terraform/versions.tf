# Terraform and Provider Version Constraints
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "CodeGuru Automation"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "code-review-automation-codeguru"
    }
  }
}