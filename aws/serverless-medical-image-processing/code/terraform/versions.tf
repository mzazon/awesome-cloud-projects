# Terraform and provider version constraints
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  default_tags {
    tags = {
      Project     = "Medical-Image-Processing"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "implementing-serverless-medical-image-processing-with-aws-healthimaging-and-step-functions"
    }
  }
}