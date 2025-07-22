# Terraform provider version constraints for TaskCat CloudFormation testing infrastructure
# This file defines the required Terraform and provider versions for consistency

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

# Default AWS provider configuration
provider "aws" {
  # Use default profile and region from AWS CLI configuration
  # Override with environment variables or terraform.tfvars as needed
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment_name
      ManagedBy   = "Terraform"
      Purpose     = "TaskCat-CloudFormation-Testing"
    }
  }
}

# Random provider for generating unique identifiers
provider "random" {}

# Archive provider for creating deployment packages
provider "archive" {}