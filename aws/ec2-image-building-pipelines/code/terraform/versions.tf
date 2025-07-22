# Terraform and Provider Version Requirements
terraform {
  required_version = ">= 1.0"
  
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

# AWS Provider Configuration
provider "aws" {
  # Default tags applied to all resources
  default_tags {
    tags = {
      Project     = "EC2ImageBuilder"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Recipe      = "ec2-image-building-pipelines"
    }
  }
}