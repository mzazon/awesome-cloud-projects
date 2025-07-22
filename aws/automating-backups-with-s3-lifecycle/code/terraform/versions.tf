# Terraform and Provider Version Configuration
# This file specifies the required Terraform version and provider versions
# for the S3 scheduled backup solution

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
      version = "~> 2.2"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "S3-Scheduled-Backups"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}