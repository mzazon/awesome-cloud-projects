# Terraform and provider version constraints
# This file defines the minimum versions required for Terraform and the AWS provider
# to ensure compatibility and access to the latest features and security updates

terraform {
  required_version = ">= 1.5"

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
      version = "~> 3.6"
    }
  }
}

# Configure the AWS Provider
# Uses environment variables AWS_REGION, AWS_ACCESS_KEY_ID, and AWS_SECRET_ACCESS_KEY
# or instance profile/IAM roles for authentication
provider "aws" {
  default_tags {
    tags = {
      Project     = "resource-cleanup-automation"
      ManagedBy   = "terraform"
      Environment = var.environment
      CostCenter  = var.cost_center
    }
  }
}