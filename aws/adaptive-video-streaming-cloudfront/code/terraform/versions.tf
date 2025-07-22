# Terraform version and provider requirements for Adaptive Bitrate Streaming solution
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  default_tags {
    tags = {
      Project     = "adaptive-bitrate-streaming"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}