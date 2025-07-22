# Terraform version and provider requirements for Dead Letter Queue Processing
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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "dlq-processing"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "dead-letter-queue-processing-sqs-lambda"
    }
  }
}