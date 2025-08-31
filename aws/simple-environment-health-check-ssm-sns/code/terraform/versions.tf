# versions.tf
# Terraform and provider version constraints for simple-environment-health-check-ssm-sns

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

# Configure the AWS provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "simple-environment-health-check"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}