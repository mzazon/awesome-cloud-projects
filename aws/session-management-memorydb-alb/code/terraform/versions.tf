# Terraform version and provider requirements
# This file defines the minimum required versions for Terraform and AWS provider

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

# Configure the AWS Provider with default tags
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "distributed-session-management"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "memorydb-alb-session-management"
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}