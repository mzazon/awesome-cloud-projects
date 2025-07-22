# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and AWS provider

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Aurora Serverless v2 Cost Optimization"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "aurora-serverless-v2-cost-optimization-patterns"
    }
  }
}