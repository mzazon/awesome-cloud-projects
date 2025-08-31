# versions.tf
# Provider version requirements for AWS basic secret management with Secrets Manager and Lambda

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  # Configuration will be taken from:
  # 1. Environment variables (AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
  # 2. AWS credentials file (~/.aws/credentials)
  # 3. IAM roles for service accounts (when running on AWS)
  
  default_tags {
    tags = {
      Project   = "SecretManagementDemo"
      ManagedBy = "Terraform"
      Recipe    = "basic-secret-management-secrets-lambda"
    }
  }
}

# Data source to get current AWS account information
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}