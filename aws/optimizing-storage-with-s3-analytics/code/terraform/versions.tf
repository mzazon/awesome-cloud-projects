# Terraform version and provider requirements for S3 Inventory and Storage Analytics Reporting
terraform {
  required_version = ">= 1.5"

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
      version = "~> 2.4"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "S3StorageAnalytics"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "s3-inventory-storage-analytics-reporting"
      CreatedDate = timestamp()
    }
  }
}