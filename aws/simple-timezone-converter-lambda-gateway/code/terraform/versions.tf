# Terraform Configuration for Simple Timezone Converter with Lambda and API Gateway
# This file defines provider requirements and version constraints

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.5"

  # Required providers and their version constraints
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Archive provider for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  # AWS region is set via AWS_DEFAULT_REGION environment variable or AWS CLI config
  # Alternative: you can specify region = var.aws_region if using a variable
  
  # Default tags applied to all resources
  default_tags {
    tags = {
      Environment   = var.environment
      Project       = "simple-timezone-converter"
      ManagedBy     = "Terraform"
      CreatedBy     = "timezone-converter-recipe"
      CostCenter    = var.cost_center
    }
  }
}

# Configure the Archive Provider
provider "archive" {
  # No specific configuration needed
}

# Configure the Random Provider  
provider "random" {
  # No specific configuration needed
}