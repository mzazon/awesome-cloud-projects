# Terraform configuration and provider requirements
# This file defines the minimum Terraform version and required providers

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
  # Configuration will be picked up from environment variables or AWS credentials file
  # Uncomment and modify the following lines if you need to specify region or profile
  # region  = var.aws_region
  # profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "Computer Vision Solutions"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "computer-vision-solutions-amazon-rekognition"
    }
  }
}

# Random provider for generating unique resource names
provider "random" {
  # No configuration needed
}