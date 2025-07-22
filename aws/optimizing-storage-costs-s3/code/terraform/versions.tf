# =============================================================================
# Terraform and Provider Version Configuration
# =============================================================================
# This file defines the minimum Terraform version and provider requirements
# for the S3 storage cost optimization solution, ensuring compatibility and
# access to the latest features and security updates.

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider - Primary provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Random Provider - For generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    
    # Time Provider - For time-based resource management
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Backend configuration for remote state storage
  # Uncomment and configure for production deployments
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "s3-storage-optimization/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# =============================================================================
# Provider Configuration
# =============================================================================
# AWS Provider configuration with default settings
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      ManagedBy     = "Terraform"
      Project       = var.project
      Environment   = var.environment
      Recipe        = "storage-cost-optimization-s3-storage-classes"
      CostCenter    = var.cost_center
      Owner         = var.owner
      DeployedBy    = "Terraform"
      LastUpdated   = timestamp()
    }
  }
}

# Random Provider configuration
provider "random" {
  # No specific configuration required
}

# Time Provider configuration
provider "time" {
  # No specific configuration required
}

# =============================================================================
# Data Sources for Provider Information
# =============================================================================
# Get information about the AWS provider
data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# =============================================================================
# Version Compatibility Information
# =============================================================================
# This configuration has been tested with the following versions:
# - Terraform: 1.5.0+
# - AWS Provider: 5.0.0+
# - Random Provider: 3.5.0+
# - Time Provider: 0.9.0+
#
# Key features utilized:
# - AWS Provider 5.x: Latest S3 resource configurations
# - Random Provider 3.x: Improved random string generation
# - Time Provider 0.9.x: Enhanced time-based resource management
# - Terraform 1.5.x: Improved validation and error handling
#
# For production deployments, consider:
# - Pinning to specific provider versions for consistency
# - Using remote backend for state management
# - Implementing state locking with DynamoDB
# - Setting up provider aliases for multi-region deployments