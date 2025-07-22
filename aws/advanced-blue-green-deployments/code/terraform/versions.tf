# Terraform and Provider Version Requirements
# This file specifies the minimum versions required for Terraform and providers

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Uncomment and configure backend as needed for state management
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "blue-green-deployments/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-lock-table"
  # }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "advanced-blue-green-deployments"
      ManagedBy   = "terraform"
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}

# Archive provider for Lambda function packaging
provider "archive" {}