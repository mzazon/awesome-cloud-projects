# Terraform and Provider Version Requirements
# This file defines the required Terraform version and AWS provider constraints
# for VPC Lattice cost analytics infrastructure

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the AWS Provider with default tags
provider "aws" {
  default_tags {
    tags = var.common_tags
  }
}

# Random provider for generating unique resource names
provider "random" {}

# Archive provider for Lambda function packaging
provider "archive" {}