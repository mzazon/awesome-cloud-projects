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
      version = "~> 3.1"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Privacy-Preserving Analytics"
      Environment = var.environment
      Recipe      = "building-privacy-preserving-data-analytics-with-aws-clean-rooms-and-quicksight"
      ManagedBy   = "Terraform"
    }
  }
}