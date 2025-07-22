# Terraform configuration and provider requirements
# This file defines the minimum Terraform version and required providers

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
  # Use default profile and region from environment
  default_tags {
    tags = {
      Project     = "hyperledger-fabric-managed-blockchain"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}