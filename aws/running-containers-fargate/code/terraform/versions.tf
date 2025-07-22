# Terraform version constraints and required providers
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "fargate-demo"
      Environment = var.environment
      Recipe      = "serverless-containers-with-fargate"
      ManagedBy   = "terraform"
    }
  }
}