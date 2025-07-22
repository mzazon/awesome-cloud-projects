# versions.tf
# Terraform version and provider requirements for AWS AppSync and DynamoDB Streams real-time data synchronization

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
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
    tags = var.default_tags
  }
}