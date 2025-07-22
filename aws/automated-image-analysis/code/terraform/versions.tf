# Terraform version and provider requirements for Amazon Rekognition image analysis solution

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "image-analysis-rekognition"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}