# Terraform and Provider Version Constraints
# This file defines the minimum required versions for Terraform and providers
# to ensure compatibility and access to required features for DynamoDB Global Tables

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

# Provider configuration for primary region
provider "aws" {
  alias  = "primary"
  region = var.primary_region
  
  default_tags {
    tags = var.default_tags
  }
}

# Provider configuration for secondary region
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  
  default_tags {
    tags = var.default_tags
  }
}

# Provider configuration for tertiary region
provider "aws" {
  alias  = "tertiary"
  region = var.tertiary_region
  
  default_tags {
    tags = var.default_tags
  }
}