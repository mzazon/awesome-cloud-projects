# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and AWS provider

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
      version = "~> 3.6"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  default_tags {
    tags = {
      Project     = "distributed-service-tracing"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "vpc-lattice-xray-tracing"
    }
  }
}