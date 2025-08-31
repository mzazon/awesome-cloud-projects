# Terraform version and provider requirements
# This file defines the minimum versions required for Terraform and AWS provider

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

# AWS Provider configuration
# Uses default AWS CLI profile or environment variables for authentication
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Simple File Backup Notifications"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "simple-file-backup-notifications-s3-sns"
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}