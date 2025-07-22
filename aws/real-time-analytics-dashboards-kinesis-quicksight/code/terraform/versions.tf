# Terraform version and provider requirements for real-time analytics dashboards
# This configuration ensures compatibility with the required AWS provider features

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
      Project     = "real-time-analytics-dashboards"
      Environment = var.environment
      ManagedBy   = "terraform"
      Purpose     = "streaming-analytics"
    }
  }
}