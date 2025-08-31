# Terraform version and provider requirements
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
  default_tags {
    tags = {
      Project     = "ServiceCatalogPortfolio"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}