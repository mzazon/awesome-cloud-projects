terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  # Configuration will be taken from environment variables or AWS CLI profile
  default_tags {
    tags = {
      Project     = "multi-tenant-resource-sharing"
      ManagedBy   = "terraform"
      Environment = var.environment
      Purpose     = "VPCLattice-RAM-MultiTenant"
    }
  }
}