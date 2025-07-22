# ===============================================================================
# Terraform Version and Provider Requirements
# ===============================================================================
# This file defines the required Terraform version and provider constraints
# for the AWS Step Functions microservices orchestration infrastructure.
# ===============================================================================

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider - Official HashiCorp AWS provider
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider - For generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Archive Provider - For creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Null Provider - For local provisioners and data sources
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    # Local Provider - For local file operations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }

  # Optional: Configure Terraform backend for state management
  # Uncomment and configure as needed for your environment
  
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "microservices-stepfunctions/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  #   
  #   # Optional: Use assumed role for cross-account access
  #   # role_arn     = "arn:aws:iam::ACCOUNT-ID:role/TerraformRole"
  # }
  
  # backend "remote" {
  #   hostname     = "app.terraform.io"
  #   organization = "your-organization"
  #   
  #   workspaces {
  #     name = "microservices-stepfunctions"
  #   }
  # }
}

# ===============================================================================
# AWS Provider Configuration
# ===============================================================================

provider "aws" {
  # Region can be specified via variable, environment variable, or AWS config
  region = var.aws_region

  # Default tags applied to all AWS resources
  default_tags {
    tags = {
      TerraformManaged = "true"
      Project         = "MicroservicesStepFunctions"
      Repository      = "recipes"
      DeployedBy      = "Terraform"
    }
  }

  # Optional: Assume role configuration for cross-account deployments
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT-ID:role/TerraformExecutionRole"
  #   session_name = "TerraformDeployment"
  #   external_id  = "unique-external-id"
  # }
}

# ===============================================================================
# Random Provider Configuration
# ===============================================================================

provider "random" {
  # No specific configuration required
}

# ===============================================================================
# Archive Provider Configuration
# ===============================================================================

provider "archive" {
  # No specific configuration required
}

# ===============================================================================
# Null Provider Configuration
# ===============================================================================

provider "null" {
  # No specific configuration required
}

# ===============================================================================
# Local Provider Configuration
# ===============================================================================

provider "local" {
  # No specific configuration required
}

# ===============================================================================
# Terraform Configuration Notes
# ===============================================================================

# Provider Version Strategy:
# - AWS Provider: Using pessimistic constraint (~> 5.0) to allow patch updates
#   while preventing breaking changes from major version updates
# - Random Provider: Using pessimistic constraint (~> 3.4) for stability
# - Archive Provider: Using pessimistic constraint (~> 2.4) for compatibility
# - Null Provider: Using pessimistic constraint (~> 3.2) for consistency
# - Local Provider: Using pessimistic constraint (~> 2.4) for file operations

# Backend Configuration:
# - S3 backend recommended for team environments with state locking via DynamoDB
# - Terraform Cloud backend recommended for managed infrastructure workflows
# - Local backend acceptable for development and testing scenarios

# AWS Provider Features:
# - Default tags ensure consistent tagging across all resources
# - Region configuration supports multi-region deployments
# - Assume role configuration enables cross-account deployments

# Version Compatibility:
# - Terraform >= 1.0 required for stable module syntax and features
# - AWS Provider >= 5.0 required for latest AWS service support
# - All providers use semantic versioning for predictable updates

# Security Considerations:
# - AWS credentials should be configured via environment variables or IAM roles
# - Terraform state files may contain sensitive information - use secure backends
# - Provider version constraints prevent unexpected security vulnerabilities

# Performance Optimizations:
# - Provider plugins are cached locally to reduce download time
# - Terraform parallelism can be tuned via TF_PARALLELISM environment variable
# - Resource dependencies are optimized for parallel creation where possible