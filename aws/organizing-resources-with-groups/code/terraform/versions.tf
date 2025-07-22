# Terraform and provider version constraints
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

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment   = var.environment
      Application   = var.application
      Purpose       = "resource-management"
      ManagedBy     = "terraform"
      Recipe        = "resource-groups-automated-resource-management"
      DeployedBy    = var.deployed_by
    }
  }
}