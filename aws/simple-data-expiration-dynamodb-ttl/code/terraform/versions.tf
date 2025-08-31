# Terraform and provider version constraints
# This file defines the minimum required versions for Terraform and AWS provider

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
      Environment   = var.environment
      Project       = "DynamoDB-TTL-Demo"
      ManagedBy     = "Terraform"
      Recipe        = "simple-data-expiration-dynamodb-ttl"
      CostCenter    = var.cost_center
      Owner         = var.owner
    }
  }
}