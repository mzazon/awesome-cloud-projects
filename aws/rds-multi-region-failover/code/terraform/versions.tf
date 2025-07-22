# Terraform version and provider requirements
# This file defines the minimum required versions for Terraform and providers

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

# Configure the AWS Provider for primary region
provider "aws" {
  region = var.primary_region
  
  default_tags {
    tags = {
      Project     = "financial-rds-multiaz"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "advanced-rds-multi-az-cross-region-failover"
    }
  }
}

# Configure the AWS Provider for secondary region
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  
  default_tags {
    tags = {
      Project     = "financial-rds-multiaz"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "advanced-rds-multi-az-cross-region-failover"
    }
  }
}