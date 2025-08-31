# Terraform and Provider Version Requirements
# This file specifies the required Terraform version and provider versions
# to ensure compatibility and reproducible deployments

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5.0"
  
  # Required providers with version constraints
  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Use latest 5.x version for newest features and bug fixes
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

# AWS Provider Configuration
# Configure the AWS Provider with default settings
provider "aws" {
  # Region can be set via:
  # 1. AWS_REGION environment variable
  # 2. AWS CLI profile configuration
  # 3. Terraform variable (uncomment and set below)
  # region = var.aws_region
  
  # Default tags applied to all resources
  default_tags {
    tags = {
      Project     = "EmailListManagement"
      ManagedBy   = "Terraform"
      Repository  = "recipes/aws/email-list-management-ses-dynamodb"
      Owner       = "DevOps"
      CostCenter  = "Marketing"
    }
  }
  
  # Skip metadata API check for faster provider initialization (optional)
  # skip_metadata_api_check = true
  
  # Skip requesting the account ID (optional)
  # skip_get_ec2_platforms = true
  
  # Skip credential validation (not recommended for production)
  # skip_credentials_validation = true
  
  # Skip region validation (not recommended)
  # skip_region_validation = true
}

# Random Provider Configuration (uses default settings)
provider "random" {}

# Archive Provider Configuration (uses default settings)
provider "archive" {}

#------------------------------------------------------------------------------
# Backend Configuration (Optional - Uncomment for Remote State)
#------------------------------------------------------------------------------

# Uncomment and configure this block to use remote state storage
# This is recommended for team environments and production deployments

# terraform {
#   backend "s3" {
#     # S3 bucket for storing Terraform state
#     bucket = "your-terraform-state-bucket"
#     key    = "email-list-management/terraform.tfstate"
#     region = "us-east-1"
#     
#     # DynamoDB table for state locking
#     dynamodb_table = "terraform-state-locks"
#     encrypt        = true
#     
#     # Workspace support
#     workspace_key_prefix = "environments"
#   }
# }

#------------------------------------------------------------------------------
# Alternative Backend Configurations
#------------------------------------------------------------------------------

# Terraform Cloud Backend (uncomment if using Terraform Cloud)
# terraform {
#   cloud {
#     organization = "your-organization"
#     
#     workspaces {
#       name = "email-list-management"
#     }
#   }
# }

# Azure Backend (uncomment if using Azure for state storage)
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "terraform-state-rg"
#     storage_account_name = "terraformstatesa"
#     container_name       = "tfstate"
#     key                  = "email-list-management.terraform.tfstate"
#   }
# }

# Google Cloud Backend (uncomment if using GCS for state storage)
# terraform {
#   backend "gcs" {
#     bucket  = "your-terraform-state-bucket"
#     prefix  = "email-list-management"
#   }
# }

#------------------------------------------------------------------------------
# Provider Feature Flags and Experiments (Optional)
#------------------------------------------------------------------------------

# Configure AWS Provider feature flags for enhanced functionality
# Uncomment specific features as needed

# provider "aws" {
#   # Enable enhanced Lambda function support
#   # experiments = [lambda_provider_logs]
#   
#   # Configure retry behavior
#   # retry_mode      = "adaptive"
#   # max_retries     = 3
#   
#   # Configure default encryption settings
#   # default_kms_key_id = "alias/terraform-default"
#   
#   # Enable S3 transfer acceleration globally
#   # s3_use_path_style = false
#   
#   # Configure STS duration
#   # assume_role_duration_seconds = 3600
# }

#------------------------------------------------------------------------------
# Version Compatibility Notes
#------------------------------------------------------------------------------

# Terraform Version Compatibility:
# - 1.5.0+: Required for import blocks and advanced language features
# - 1.6.0+: Recommended for test framework and configuration validation
# - 1.7.0+: Latest features and performance improvements

# AWS Provider Version Compatibility:
# - 5.0+: Latest resource support and AWS service features
# - 5.20+: Enhanced Lambda and DynamoDB functionality
# - 5.30+: Improved SES v2 API support

# Provider Update Strategy:
# - Use ~> 5.0 to allow minor version updates while maintaining compatibility
# - Test thoroughly before updating to major versions
# - Review provider changelog before updates

#------------------------------------------------------------------------------
# Development and Testing Configuration
#------------------------------------------------------------------------------

# For development environments, you may want to use local state
# and skip certain validations for faster iteration

# Development provider configuration (comment out for production)
# provider "aws" {
#   # Use localstack for local development
#   endpoints {
#     apigateway     = "http://localhost:4566"
#     cloudformation = "http://localhost:4566"
#     cloudwatch     = "http://localhost:4566"
#     cloudwatchlogs = "http://localhost:4566"
#     dynamodb       = "http://localhost:4566"
#     ec2            = "http://localhost:4566"
#     es             = "http://localhost:4566"
#     firehose       = "http://localhost:4566"
#     iam            = "http://localhost:4566"
#     kinesis        = "http://localhost:4566"
#     lambda         = "http://localhost:4566"
#     route53        = "http://localhost:4566"
#     redshift       = "http://localhost:4566"
#     s3             = "http://localhost:4566"
#     secretsmanager = "http://localhost:4566"
#     ses            = "http://localhost:4566"
#     sns            = "http://localhost:4566"
#     sqs            = "http://localhost:4566"
#     ssm            = "http://localhost:4566"
#     stepfunctions  = "http://localhost:4566"
#     sts            = "http://localhost:4566"
#   }
#   
#   access_key                  = "test"
#   secret_key                  = "test"
#   region                      = "us-east-1"
#   s3_use_path_style          = true
#   skip_credentials_validation = true
#   skip_metadata_api_check    = true
#   skip_requesting_account_id = true
# }