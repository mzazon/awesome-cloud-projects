# Terraform provider requirements for multi-branch CI/CD pipeline
# This file specifies the required providers and their versions for the multi-branch pipeline infrastructure

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
    
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "multi-branch-cicd"
      Environment = var.environment
      CreatedBy   = "terraform"
      Owner       = var.owner
    }
  }
}