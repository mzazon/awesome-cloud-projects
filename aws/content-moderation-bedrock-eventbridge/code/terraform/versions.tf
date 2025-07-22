# Terraform configuration and provider requirements
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ContentModeration"
      Environment = var.environment
      Recipe      = "building-intelligent-content-moderation-amazon-bedrock-eventbridge"
      ManagedBy   = "Terraform"
    }
  }
}