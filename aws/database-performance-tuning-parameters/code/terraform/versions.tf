# Terraform version and provider requirements for database performance tuning recipe
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
      Project      = "Database Performance Tuning"
      Recipe       = "database-performance-tuning-parameter-groups"
      Environment  = var.environment
      ManagedBy    = "terraform"
      CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
    }
  }
}