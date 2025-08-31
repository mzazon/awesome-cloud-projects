# Terraform version and provider requirements
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

# AWS provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "simple-daily-quote-generator"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}