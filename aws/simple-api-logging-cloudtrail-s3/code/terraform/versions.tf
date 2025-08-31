# Terraform and Provider Version Requirements
# This file defines the minimum versions for Terraform and the AWS provider
# to ensure compatibility with the CloudTrail, S3, CloudWatch, IAM, and SNS resources

terraform {
  # Require Terraform 1.0 or higher for enhanced validation and features
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider - using latest stable version for CloudTrail enhancements
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

# Configure the AWS Provider with default tags for consistent resource tagging
provider "aws" {
  default_tags {
    tags = {
      Project     = "simple-api-logging-cloudtrail-s3"
      ManagedBy   = "terraform"
      Environment = var.environment
      Recipe      = "CloudTrail API Logging with S3 and CloudWatch"
    }
  }
}