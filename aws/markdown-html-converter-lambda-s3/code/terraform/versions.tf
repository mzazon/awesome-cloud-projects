# Terraform and provider version requirements
# This file specifies the minimum versions required for Terraform and providers

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# AWS Provider Configuration
# Configure the AWS provider with default tags applied to all resources
provider "aws" {
  default_tags {
    tags = {
      Project     = "markdown-html-converter"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "markdown-html-converter-lambda-s3"
    }
  }
}

# Archive Provider Configuration
# Used for creating deployment packages for Lambda functions
provider "archive" {
  # No specific configuration needed
}

# Random Provider Configuration  
# Used for generating unique identifiers and suffixes
provider "random" {
  # No specific configuration needed
}