# Terraform configuration for feature flags with CloudWatch Evidently
# This file defines the required Terraform and provider versions

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

# Configure the AWS provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.default_tags
  }
}