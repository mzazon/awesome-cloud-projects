# Terraform and provider version constraints
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
      Environment   = var.environment
      Application   = "Financial-QLDB"
      ManagedBy     = "Terraform"
      CostCenter    = var.cost_center
      Owner         = var.owner
    }
  }
}