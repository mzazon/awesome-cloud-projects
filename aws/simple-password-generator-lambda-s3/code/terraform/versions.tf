# Terraform and provider version requirements
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS provider
provider "aws" {
  # Use default credentials and region from AWS CLI or environment variables
  default_tags {
    tags = {
      Project     = "Simple Password Generator"
      ManagedBy   = "Terraform"
      Environment = var.environment
      CreatedBy   = "terraform-recipe"
    }
  }
}