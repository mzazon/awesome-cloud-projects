# Terraform version requirements and provider configuration
# This file defines the minimum Terraform version and AWS provider version
# required for the S3 Tables analytics infrastructure

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.84"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the AWS provider with default tags for resource management
provider "aws" {
  default_tags {
    tags = {
      Project     = "S3TablesAnalytics"
      Environment = var.environment
      CreatedBy   = "Terraform"
      Recipe      = "analytics-optimized-data-storage-s3-tables"
    }
  }
}