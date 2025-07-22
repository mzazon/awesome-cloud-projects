# Terraform configuration for AWS Cloud9 developer environments
# This file defines the required Terraform and provider versions

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Cloud9-Development-Environment"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "developer-environments-aws-cloud9"
    }
  }
}

# Configure the Random Provider
provider "random" {}