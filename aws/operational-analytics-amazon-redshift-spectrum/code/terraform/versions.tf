# Terraform and provider version constraints for Redshift Spectrum operational analytics
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

# AWS provider configuration
provider "aws" {
  default_tags {
    tags = {
      Project     = "operational-analytics-redshift-spectrum"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}