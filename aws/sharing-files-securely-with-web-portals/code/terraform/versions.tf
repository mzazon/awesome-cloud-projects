# Terraform version and provider requirements for secure file sharing with AWS Transfer Family
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.83"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "SecureFileSharing"
      ManagedBy   = "Terraform"
      Recipe      = "secure-file-sharing-transfer-family-web-apps"
    }
  }
}

# Random provider for generating unique identifiers
provider "random" {}