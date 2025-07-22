# Terraform and Provider Version Requirements
# This file specifies the required versions for Terraform and AWS provider
# to ensure compatibility and reproducible deployments

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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "EventBridge-Replay-Demo"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CreatedBy   = "EventReplayRecipe"
    }
  }
}