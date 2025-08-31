# Terraform and Provider Version Requirements
# This file defines the minimum versions required for Terraform and AWS provider

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

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "infrastructure-monitoring-quick-setup"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "Systems Manager Quick Setup"
    }
  }
}

# Random Provider for unique resource naming
provider "random" {}