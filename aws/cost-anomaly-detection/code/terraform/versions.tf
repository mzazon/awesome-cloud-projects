# Terraform and provider version requirements
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

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cost-anomaly-detection"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "cost-anomaly-detection-aws-cost-anomaly-detector"
    }
  }
}