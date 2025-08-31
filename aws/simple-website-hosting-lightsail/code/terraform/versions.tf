# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and AWS provider
# to ensure compatibility and access to all required Lightsail resources

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
# Lightsail is available in most AWS regions
# Default region can be overridden via variables or environment
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Simple Website Hosting"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "simple-website-hosting-lightsail"
    }
  }
}

# Random provider for generating unique resource identifiers
provider "random" {}