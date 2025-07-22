# Terraform version and provider configuration for Aurora database migration solution
# This file defines the minimum Terraform version and required providers

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

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Aurora Database Migration"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "Database Migration Infrastructure"
      Recipe      = "databases-aurora-minimal-downtime"
    }
  }
}