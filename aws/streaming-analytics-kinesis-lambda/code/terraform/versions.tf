# Terraform configuration for serverless real-time analytics pipeline
# This file defines the required providers and their version constraints

terraform {
  required_version = ">= 1.5"

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

# Configure the AWS Provider
provider "aws" {
  default_tags {
    tags = {
      Project     = "ServerlessAnalytics"
      Environment = var.environment
      CreatedBy   = "Terraform"
      Recipe      = "serverless-realtime-analytics-kinesis-lambda"
    }
  }
}