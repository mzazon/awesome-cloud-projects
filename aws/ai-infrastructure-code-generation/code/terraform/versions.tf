# Terraform and Provider Version Requirements
# This file specifies the minimum Terraform version and required providers
# for the AI-powered infrastructure code generation solution

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5.0"

  # Required provider configurations
  required_providers {
    # AWS Provider for core infrastructure resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Archive provider for Lambda function packaging
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  # AWS region will be set via environment variable or AWS CLI configuration
  # Default tags applied to all resources
  default_tags {
    tags = {
      Project     = "AI-Powered Infrastructure Generation"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Recipe      = "amazon-q-developer-infrastructure-composer"
    }
  }
}