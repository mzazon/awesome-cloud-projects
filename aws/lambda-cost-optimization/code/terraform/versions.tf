# Terraform provider version constraints for AWS Lambda Cost Optimization with Compute Optimizer
# This configuration ensures compatibility and stability across different environments

terraform {
  required_version = ">= 1.5"

  required_providers {
    # AWS Provider for all AWS resources
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

    # Null provider for local provisioners and scripting
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Configure AWS Provider with default tags for cost tracking and management
provider "aws" {
  default_tags {
    tags = {
      Project             = "lambda-cost-optimization"
      Environment         = var.environment
      ManagedBy          = "terraform"
      CostCenter         = var.cost_center
      Purpose            = "compute-optimizer-demo"
      Recipe             = "lambda-cost-compute-optimizer"
      OptimizationTarget = "cost-performance"
    }
  }
}