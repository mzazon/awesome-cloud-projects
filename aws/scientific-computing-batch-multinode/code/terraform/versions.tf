# =============================================================================
# AWS Batch Multi-Node Parallel Jobs - Provider Versions & Configuration
# Terraform and provider version constraints for scientific computing infrastructure
# =============================================================================

terraform {
  required_version = ">= 1.5"

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

  # Uncomment the backend configuration below if using remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "scientific-computing/batch-multi-node/terraform.tfstate"
  #   region         = "us-west-2"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

# =============================================================================
# AWS Provider Configuration
# =============================================================================

provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = merge({
      Project             = var.project_name
      Environment         = var.environment
      ManagedBy          = "terraform"
      Purpose            = "distributed-scientific-computing"
      InfrastructureType = "aws-batch-multi-node"
      CreatedDate        = formatdate("YYYY-MM-DD", timestamp())
    }, var.additional_tags)
  }

  # Retry configuration for improved reliability
  retry_mode = "adaptive"
  max_retries = 3

  # Skip metadata API check if running in environments without EC2 metadata
  # skip_metadata_api_check = true

  # Uncomment and configure if using assume role
  # assume_role {
  #   role_arn = "arn:aws:iam::ACCOUNT-ID:role/TerraformRole"
  # }
}

# =============================================================================
# Random Provider Configuration
# =============================================================================

provider "random" {
  # Random provider doesn't require additional configuration
}

# =============================================================================
# Terraform Cloud / Enterprise Configuration (Optional)
# =============================================================================

# Uncomment if using Terraform Cloud or Terraform Enterprise
# terraform {
#   cloud {
#     organization = "your-organization"
#     workspaces {
#       name = "scientific-computing-batch"
#     }
#   }
# }

# =============================================================================
# Provider Feature Flags & Experimental Features
# =============================================================================

# Configure AWS provider experimental features if needed
# provider "aws" {
#   experiments = [
#     # Add experimental features here if needed
#   ]
# }

# =============================================================================
# Version Constraints Notes
# =============================================================================

# AWS Provider Version ~> 5.0:
# - Supports latest AWS Batch features including multi-node parallel jobs
# - Includes enhanced security group rules and VPC endpoints
# - Full support for EFS encryption and performance modes
# - Compatible with latest EC2 instance types including HPC-optimized instances

# Terraform Version >= 1.5:
# - Required for advanced validation rules and functions
# - Supports conditional expressions and dynamic blocks used in this configuration
# - Enhanced state management and provider dependency resolution
# - Improved error handling and debugging capabilities

# Random Provider Version ~> 3.1:
# - Stable random resource generation for unique naming
# - Compatible with Terraform >= 1.0
# - Reliable for generating suffixes and passwords