# Terraform version and provider requirements for Amazon Connect contact center solution
# This configuration ensures compatibility with the required AWS provider features

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
}

# Configure the AWS provider with default tags for resource management
provider "aws" {
  default_tags {
    tags = {
      Project     = "CustomContactCenter"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "custom-contact-center-solutions-amazon-connect"
    }
  }
}