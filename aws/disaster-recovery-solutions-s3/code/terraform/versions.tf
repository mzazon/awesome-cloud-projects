# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and AWS provider

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

# Primary region provider configuration
provider "aws" {
  alias  = "primary"
  region = var.primary_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Purpose     = "DisasterRecovery"
      CostCenter  = var.cost_center
      ManagedBy   = "Terraform"
    }
  }
}

# Secondary region provider configuration for cross-region replication
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Purpose     = "DisasterRecovery"
      CostCenter  = var.cost_center
      ManagedBy   = "Terraform"
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}