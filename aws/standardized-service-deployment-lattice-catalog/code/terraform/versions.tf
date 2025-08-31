# Terraform version and provider requirements
# This file defines the minimum Terraform version and required providers for the VPC Lattice Service Catalog solution

terraform {
  required_version = ">= 1.5"

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
  # AWS region and credentials should be configured via:
  # - Environment variables (AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
  # - AWS CLI configuration (~/.aws/config and ~/.aws/credentials)
  # - IAM roles for EC2 instances or other AWS services
  # - AWS SSO profiles

  default_tags {
    tags = {
      Purpose     = "VPCLatticeStandardization"
      ManagedBy   = "Terraform"
      Recipe      = "standardized-service-deployment-lattice-catalog"
      Environment = var.environment
    }
  }
}