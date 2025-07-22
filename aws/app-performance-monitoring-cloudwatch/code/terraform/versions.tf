# =============================================================================
# Provider Version Requirements and Configuration
# 
# This file defines the required Terraform version and provider versions
# for the automated application performance monitoring infrastructure.
# =============================================================================

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5.0"
  
  # Required provider configurations with version constraints
  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique resource identifiers
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

# =============================================================================
# AWS Provider Configuration
# =============================================================================

provider "aws" {
  # Region can be set via AWS_REGION environment variable,
  # AWS CLI configuration, or the region variable
  region = var.aws_region
  
  # Default tags applied to all resources
  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "automated-application-performance-monitoring"
      Repository  = "cloud-recipes"
    }
  }
}

# =============================================================================
# Provider Feature Configurations
# =============================================================================

# AWS Provider features for specific service behaviors
# These configurations help ensure consistent behavior across different AWS services
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  
  # Default tags for resources that might need to be created in us-east-1
  # (e.g., for global services or CloudFront configurations)
  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "automated-application-performance-monitoring"
      Repository  = "cloud-recipes"
      Region      = "us-east-1"
    }
  }
}

# =============================================================================
# Terraform Backend Configuration (Optional)
# =============================================================================

# Uncomment and configure the backend block below to use remote state storage
# This is recommended for production deployments and team collaboration

# terraform {
#   backend "s3" {
#     # S3 bucket for storing Terraform state
#     bucket = "your-terraform-state-bucket"
#     key    = "monitoring/automated-application-performance-monitoring/terraform.tfstate"
#     region = "us-east-1"
#     
#     # DynamoDB table for state locking
#     dynamodb_table = "terraform-state-locks"
#     
#     # Enable encryption for state file
#     encrypt = true
#     
#     # Optional: KMS key for state encryption
#     # kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
#   }
# }

# Alternative backend configurations:

# Remote backend using Terraform Cloud
# terraform {
#   cloud {
#     organization = "your-organization"
#     workspaces {
#       name = "app-performance-monitoring"
#     }
#   }
# }

# Azure backend (for hybrid cloud scenarios)
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "terraform-state-rg"
#     storage_account_name = "terraformstatestorage"
#     container_name      = "terraform-state"
#     key                 = "monitoring/automated-application-performance-monitoring.tfstate"
#   }
# }

# =============================================================================
# Terraform Configuration Settings
# =============================================================================

# Configure Terraform behavior and experimental features
terraform {
  # Enable provider installation from the Terraform Registry
  required_providers {
    # Specify the exact versions for production deployments
    # Use ~> for minor version updates, = for exact versions
    
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40" # Allows 5.40.x versions
      
      # Configuration aliases for multiple AWS accounts or regions
      # configuration_aliases = [aws.us_east_1, aws.backup]
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
  
  # Experimental features (use with caution in production)
  # experiments = [module_variable_optional_attrs]
}

# =============================================================================
# Provider Version Constraints and Compatibility
# =============================================================================

# Version constraints explanation:
# ~> 5.0   : Allows 5.x versions (pessimistic constraint)
# >= 5.0   : Allows 5.0 and higher versions
# < 6.0    : Allows versions less than 6.0
# = 5.40.0 : Exact version match

# AWS Provider version compatibility:
# - Version 5.x: Latest stable version with all features
# - Minimum version 5.0 required for:
#   * CloudWatch Application Signals support
#   * Enhanced EventBridge features
#   * Latest Lambda runtime support
#   * Improved resource tagging capabilities

# =============================================================================
# Local Development Overrides (Development Only)
# =============================================================================

# The following block can be uncommented for local development
# to override provider versions or use local provider builds
# DO NOT use in production environments

# terraform {
#   required_providers {
#     aws = {
#       source = "terraform.local/local/aws"
#       version = "99.99.99"
#     }
#   }
# }

# =============================================================================
# Provider Configuration Validation
# =============================================================================

# Data sources to validate provider configuration
data "aws_caller_identity" "validation" {}
data "aws_region" "validation" {}
data "aws_partition" "validation" {}

# Local values for provider validation
locals {
  # Validate AWS provider configuration
  aws_account_valid = length(data.aws_caller_identity.validation.account_id) == 12
  aws_region_valid  = length(data.aws_region.validation.name) >= 9
  aws_partition_valid = contains(["aws", "aws-cn", "aws-us-gov"], data.aws_partition.validation.partition)
  
  # Provider configuration summary
  provider_config = {
    terraform_version = ">=1.5.0"
    aws_provider_version = "~>5.0"
    account_id = data.aws_caller_identity.validation.account_id
    region = data.aws_region.validation.name
    partition = data.aws_partition.validation.partition
  }
}

# Validation checks using postconditions (Terraform 1.2+)
check "provider_validation" {
  assert {
    condition     = local.aws_account_valid
    error_message = "AWS Account ID validation failed - ensure AWS provider is properly configured"
  }
  
  assert {
    condition     = local.aws_region_valid
    error_message = "AWS Region validation failed - ensure valid region is configured"
  }
  
  assert {
    condition     = local.aws_partition_valid
    error_message = "AWS Partition validation failed - unsupported AWS partition"
  }
}