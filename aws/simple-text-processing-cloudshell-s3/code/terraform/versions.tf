# Provider and Terraform version requirements
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.5.0"

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

  # Optional: Configure backend for state management
  # Uncomment and configure for production deployments
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "text-processing/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project     = "TextProcessingDemo"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "simple-text-processing-cloudshell-s3"
    }
  }
}

# Configure random provider for unique resource naming
provider "random" {}