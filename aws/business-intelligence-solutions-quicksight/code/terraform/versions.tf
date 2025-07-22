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
      version = "~> 3.4"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "QuickSight-BI-Solutions"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "business-intelligence-solutions-quicksight"
    }
  }
}

# Random provider for generating unique identifiers
provider "random" {}