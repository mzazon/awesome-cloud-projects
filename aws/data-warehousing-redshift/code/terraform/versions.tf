# Terraform version and provider requirements for Amazon Redshift Data Warehouse
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "redshift-data-warehouse"
      ManagedBy   = "terraform"
      Recipe      = "data-warehousing-solutions-amazon-redshift"
      Owner       = var.owner
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}