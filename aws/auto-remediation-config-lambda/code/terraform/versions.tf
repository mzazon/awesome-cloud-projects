# Terraform version and provider requirements
# This file defines the minimum versions for Terraform and AWS provider
# to ensure compatibility with the resources used in this configuration

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

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "AWS Config Auto Remediation"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "auto-remediation-aws-config-lambda"
    }
  }
}