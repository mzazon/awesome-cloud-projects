# Terraform version and provider requirements
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
      Project     = "CloudFront-S3-CDN"
      Environment = var.environment
      Recipe      = "content-delivery-networks-cloudfront-s3"
      ManagedBy   = "Terraform"
    }
  }
}

# Configure the Random Provider for unique resource naming
provider "random" {
  # No configuration needed
}