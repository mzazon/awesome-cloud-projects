# Terraform version and provider requirements
# This file specifies the minimum Terraform version and required providers

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

# AWS Provider configuration
provider "aws" {
  default_tags {
    tags = {
      Project   = "URLShortener"
      ManagedBy = "Terraform"
    }
  }
}