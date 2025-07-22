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
    tags = {
      Project     = "Database Security with IAM Authentication"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "database-security-encryption-iam-database-authentication"
    }
  }
}

# Provider configuration for random resources
provider "random" {}