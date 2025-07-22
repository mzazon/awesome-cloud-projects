# versions.tf - Terraform and provider version constraints
# This file defines the required Terraform version and provider versions
# for the DynamoDB Global Tables multi-region infrastructure

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # AWS provider for primary region resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Archive provider for Lambda function packaging
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Provider configuration aliases for multi-region deployment
# Primary region provider (default)
provider "aws" {
  region = var.primary_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Recipe      = "dynamodb-global-tables-multi-region"
    }
  }
}

# Secondary region provider
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Recipe      = "dynamodb-global-tables-multi-region"
    }
  }
}

# Tertiary region provider
provider "aws" {
  alias  = "tertiary"
  region = var.tertiary_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Recipe      = "dynamodb-global-tables-multi-region"
    }
  }
}