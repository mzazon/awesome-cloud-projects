# Terraform and Provider Version Requirements
# This file specifies the minimum versions for Terraform and AWS provider

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

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "fine-grained-access-control-iam-policies-conditions"
      ManagedBy   = "Terraform"
    }
  }
}

# Random Provider Configuration
provider "random" {}