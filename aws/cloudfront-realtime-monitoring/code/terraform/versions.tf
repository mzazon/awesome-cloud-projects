# CloudFront Real-time Monitoring and Analytics - Terraform Provider Configuration
# This file defines the required Terraform and provider versions along with default tags

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner
      Purpose     = "CloudFront Real-time Monitoring and Analytics"
      CreatedBy   = "Terraform"
      Recipe      = "cloudfront-realtime-monitoring-analytics"
    }
  }
}

# Configure the Random Provider for unique resource naming
provider "random" {}

# Configure the Archive Provider for Lambda function packaging
provider "archive" {}