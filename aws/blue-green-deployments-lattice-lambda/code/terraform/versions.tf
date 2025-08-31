# Terraform and provider version requirements
terraform {
  required_version = ">= 1.5"

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
      version = "~> 3.5"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "blue-green-deployments"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "blue-green-deployments-lattice-lambda"
    }
  }
}