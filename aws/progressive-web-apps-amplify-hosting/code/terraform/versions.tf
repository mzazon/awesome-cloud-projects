# Terraform and Provider Version Requirements
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

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "PWA-Amplify-Hosting"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "Progressive Web App Infrastructure"
    }
  }
}