# Terraform configuration and provider requirements
# This file defines the minimum Terraform version and required providers

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "custom-entity-recognition-comprehend-classification"
      ManagedBy   = "Terraform"
    }
  }
}