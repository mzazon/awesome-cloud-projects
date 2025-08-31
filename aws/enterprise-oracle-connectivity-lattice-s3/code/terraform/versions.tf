# Terraform and Provider Requirements
# Enterprise Oracle Database Connectivity with VPC Lattice and S3

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "enterprise-oracle-connectivity"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "enterprise-oracle-connectivity-lattice-s3"
    }
  }
}