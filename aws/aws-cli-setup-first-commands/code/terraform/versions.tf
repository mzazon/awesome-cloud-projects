# Terraform and Provider Version Requirements
# This file specifies the required versions for Terraform and AWS provider
# to ensure compatibility and reproducible deployments

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider for generating unique identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Local Provider for creating local files (templates)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }

  # Optional: Configure backend for state management
  # Uncomment and configure as needed for your environment
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "aws-cli-tutorial/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# Configure the AWS Provider
provider "aws" {
  # Configuration will be taken from environment variables, AWS credentials file,
  # or IAM roles when running on EC2/Lambda
  
  # Optional: Specify region if not set via environment variables or credentials
  # region = var.aws_region

  # Optional: Add common tags to all resources created by this provider
  default_tags {
    tags = {
      Project       = "AWS CLI Tutorial"
      Recipe        = "aws-cli-setup-first-commands"
      ManagedBy     = "Terraform"
      Repository    = "https://github.com/your-org/recipes"
      Documentation = "aws/aws-cli-setup-first-commands/aws-cli-setup-first-commands.md"
    }
  }
}