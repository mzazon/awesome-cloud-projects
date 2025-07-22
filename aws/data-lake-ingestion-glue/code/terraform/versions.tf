# Terraform and Provider Version Requirements
# This configuration ensures compatibility and reproducibility across environments

terraform {
  required_version = ">= 1.6.0"
  
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

# Configure the AWS Provider with default tags
provider "aws" {
  default_tags {
    tags = {
      Project     = "DataLakeIngestionPipeline"
      Environment = var.environment
      CreatedBy   = "Terraform"
      Repository  = "recipes"
    }
  }
}