# Terraform and Provider Version Requirements
# This file specifies the minimum required versions for Terraform and AWS provider

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  # Region will be set via AWS_DEFAULT_REGION environment variable
  # or through terraform variables
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Simple Random Data API"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "simple-random-data-api-lambda-gateway"
    }
  }
}