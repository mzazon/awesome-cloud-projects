# Terraform and Provider Requirements
# This file defines the required providers and their version constraints

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Uncomment and configure for production deployments
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "sso/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "AWS-SSO-External-IdP"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "aws-single-sign-on-external-identity-providers"
    }
  }
}

# Configure the Random Provider
provider "random" {}

# Configure the Time Provider
provider "time" {}