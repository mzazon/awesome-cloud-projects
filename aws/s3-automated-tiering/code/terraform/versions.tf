# Terraform and Provider Version Constraints
# This file defines the minimum versions required for Terraform and providers

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
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "S3 Intelligent Tiering Demo"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "intelligent-tiering-lifecycle-management-s3"
    }
  }
}