# Terraform version and provider requirements
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

  # Backend configuration for remote state management
  # Configure during terraform init with:
  # terraform init -backend-config="bucket=your-state-bucket" \
  #                -backend-config="key=terraform.tfstate" \
  #                -backend-config="region=us-east-1" \
  #                -backend-config="dynamodb_table=your-lock-table" \
  #                -backend-config="encrypt=true"
  backend "s3" {
    # Backend configuration will be provided during init
  }
}

# AWS Provider configuration with default tags
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "infrastructure-as-code-terraform-aws"
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}