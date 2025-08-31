# Terraform version and provider requirements for AWS VPC Lattice Resource Gateway
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

# Configure AWS Provider with default tags for all resources
provider "aws" {
  default_tags {
    tags = {
      Project     = "VPC-Lattice-Database-Access"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}