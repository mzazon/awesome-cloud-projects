# Terraform version and provider requirements
# This file defines the minimum Terraform version and required providers
# for the weather alert notifications infrastructure

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "weather-alert-notifications"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}

# Archive provider for creating Lambda deployment packages
provider "archive" {}