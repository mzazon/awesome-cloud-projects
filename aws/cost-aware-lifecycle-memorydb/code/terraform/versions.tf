# Terraform and Provider Version Requirements
# This file defines the required Terraform version and AWS provider constraints
# to ensure consistent infrastructure deployment across environments

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider for core infrastructure services
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive Provider for Lambda function deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  # These tags support cost allocation and resource management
  default_tags {
    tags = {
      Project     = "Cost-Aware-MemoryDB-Lifecycle"
      Environment = var.environment
      Recipe      = "cost-aware-resource-lifecycle-eventbridge-scheduler-memorydb"
      ManagedBy   = "Terraform"
      CostCenter  = var.cost_center
    }
  }
}

# Random Provider for unique identifiers
provider "random" {}

# Archive Provider for Lambda packaging
provider "archive" {}