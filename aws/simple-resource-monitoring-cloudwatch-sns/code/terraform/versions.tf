# Terraform and Provider Version Requirements
# This configuration ensures compatibility with the latest stable versions

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Simple Resource Monitoring"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "simple-resource-monitoring-cloudwatch-sns"
    }
  }
}