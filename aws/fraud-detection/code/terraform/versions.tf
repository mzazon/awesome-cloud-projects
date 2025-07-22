# Terraform and provider version requirements
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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  # Region will be set via environment variable AWS_DEFAULT_REGION
  # or aws configure, or can be set explicitly here
  
  default_tags {
    tags = {
      Project     = "fraud-detection-system"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "fraud-detection-systems-amazon-fraud-detector"
    }
  }
}