# Terraform and Provider Version Requirements
# This file defines the minimum Terraform version and required providers
# for the Neptune Graph Database Recommendation Engine infrastructure

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
      Project     = "neptune-recommendation-engine"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "graph-databases-recommendation-engines-amazon-neptune"
    }
  }
}