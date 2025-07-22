# Terraform and Provider Version Constraints
# This file defines the required Terraform version and AWS provider version
# for Analyzing Time-Series Data with Timestream

terraform {
  # Require Terraform version 1.0 or higher for stable features
  required_version = ">= 1.0"

  # Define required providers and their version constraints
  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Use AWS provider v5.x for latest Timestream features
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive provider for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Configure the AWS Provider with default tags
provider "aws" {
  # Default tags applied to all resources that support tagging
  default_tags {
    tags = {
      Project             = "timestream-iot-solution"
      Environment         = var.environment
      ManagedBy          = "terraform"
      Recipe             = "time-series-data-solutions-amazon-timestream"
      CostCenter         = var.cost_center
      DataClassification = "internal"
    }
  }
}