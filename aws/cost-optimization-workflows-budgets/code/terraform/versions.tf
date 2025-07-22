# Terraform provider configuration for AWS Cost Optimization Hub and Budgets
# This file defines the required Terraform version and AWS provider requirements

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "cost-optimization-workflows"
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}