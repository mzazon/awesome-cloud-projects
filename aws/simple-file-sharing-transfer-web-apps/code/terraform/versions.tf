# AWS Transfer Family Web Apps - Terraform Provider Requirements
# This configuration specifies the required providers and their versions
# for the Simple File Sharing with Transfer Family Web Apps infrastructure

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

# Configure the AWS Provider
provider "aws" {
  # Configuration will be taken from environment variables, AWS CLI config,
  # or IAM instance profile (when running on EC2)
  
  default_tags {
    tags = {
      Project     = "simple-file-sharing"
      Environment = var.environment
      ManagedBy   = "terraform"
      Purpose     = "transfer-family-web-apps"
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}