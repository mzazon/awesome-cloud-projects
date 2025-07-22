# AWS Amplify DataStore - Terraform Version and Provider Configuration
# This file defines the required Terraform version and provider configurations
# for deploying offline-first mobile applications with AWS Amplify DataStore.

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
    tags = var.default_tags
  }
}

# Random provider for generating unique resource names
provider "random" {}