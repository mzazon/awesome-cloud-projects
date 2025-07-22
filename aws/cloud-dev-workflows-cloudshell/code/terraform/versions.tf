# Terraform and provider version requirements
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# AWS provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cloud-based-development-workflows"
      Environment = var.environment
      Recipe      = "cloudshell-codecommit"
      ManagedBy   = "terraform"
    }
  }
}