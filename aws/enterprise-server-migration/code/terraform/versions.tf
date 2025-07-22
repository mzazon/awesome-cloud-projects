# versions.tf - Terraform and provider version constraints
# This file defines the required Terraform version and provider versions
# for the AWS Application Migration Service infrastructure

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
      Project     = "AWS-Application-Migration-Service"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "large-scale-server-migration-aws-application-migration-service"
    }
  }
}