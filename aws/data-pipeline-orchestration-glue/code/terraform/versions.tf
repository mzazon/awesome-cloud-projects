# versions.tf - Terraform and provider version constraints
# This file defines the required Terraform version and provider versions
# for the AWS Glue Workflows data pipeline orchestration solution

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

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "data-pipeline-orchestration"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "aws-glue-workflows"
    }
  }
}

# Configure the Random Provider for generating unique resource names
provider "random" {}