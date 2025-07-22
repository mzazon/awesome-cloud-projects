# Provider versions and requirements for AWS Transfer Family Web Apps infrastructure

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
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  # Default tags for all resources
  default_tags {
    tags = {
      Project     = "Self-Service File Management"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "self-service-file-management-transfer-family-web-apps-identity-center"
    }
  }
}