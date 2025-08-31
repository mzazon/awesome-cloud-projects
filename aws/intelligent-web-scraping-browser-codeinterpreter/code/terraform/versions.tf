# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and all providers
# to ensure compatibility and access to the latest features

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.6.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.30.0, < 6.0.0"
    }

    # Random provider for generating unique identifiers
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.0, < 4.0.0"
    }

    # Archive provider for creating ZIP files for Lambda deployment
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0, < 3.0.0"
    }

    # Template provider for processing template files (if needed)
    template = {
      source  = "hashicorp/template"
      version = ">= 2.2.0, < 3.0.0"
    }
  }

  # Optional: Specify backend configuration for state management
  # Uncomment and configure the backend block below for production deployments
  
  # backend "s3" {
  #   bucket  = "your-terraform-state-bucket"
  #   key     = "intelligent-scraping/terraform.tfstate"
  #   region  = "us-east-1"
  #   encrypt = true
  #   
  #   # Optional: DynamoDB table for state locking
  #   dynamodb_table = "terraform-state-lock"
  # }
}

#==============================================================================
# PROVIDER CONFIGURATIONS
#==============================================================================

# AWS Provider Configuration
provider "aws" {
  # Use the region specified in variables
  region = var.aws_region

  # Default tags applied to all resources created by this provider
  default_tags {
    tags = {
      Terraform     = "true"
      Project       = "IntelligentWebScraping"
      Environment   = var.environment
      Repository    = "recipes/aws/intelligent-web-scraping-browser-codeinterpreter"
      ManagedBy     = "Terraform"
      CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
      
      # Cost allocation tags
      CostCenter    = var.cost_center
      BusinessUnit  = var.business_unit
    }
  }

  # Assume role configuration (optional, for cross-account deployments)
  # Uncomment and configure if deploying to a different AWS account
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT-ID:role/TerraformExecutionRole"
  #   session_name = "intelligent-scraping-deployment"
  # }

  # Retry configuration for handling AWS API throttling
  retry_mode = "adaptive"
  max_retries = 3

  # Skip metadata API check (useful for CI/CD environments)
  skip_metadata_api_check = false

  # Skip region validation (only set to true if using unsupported regions)
  skip_region_validation = false

  # Skip credentials validation (only for specific use cases)
  skip_credentials_validation = false

  # Skip requesting account ID (can improve performance in some scenarios)
  skip_requesting_account_id = false
}

# Random Provider Configuration
provider "random" {
  # No specific configuration required for the random provider
}

# Archive Provider Configuration  
provider "archive" {
  # No specific configuration required for the archive provider
}

# Template Provider Configuration
provider "template" {
  # No specific configuration required for the template provider
}

#==============================================================================
# DATA SOURCES FOR PROVIDER INFORMATION
#==============================================================================

# Get current AWS caller identity for account ID and other details
data "aws_caller_identity" "current" {}

# Get current AWS region information
data "aws_region" "current" {}

# Get AWS partition information (useful for different AWS partitions like GovCloud)
data "aws_partition" "current" {}

# Available AWS availability zones in the current region
data "aws_availability_zones" "available" {
  state = "available"
}

#==============================================================================
# LOCAL VALUES FOR PROVIDER CONFIGURATIONS
#==============================================================================

locals {
  # Account information from data sources
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  # Construct ARN prefixes for different services
  arn_prefix = "arn:${local.partition}:*:${local.region}:${local.account_id}"
  
  # Provider configuration metadata
  terraform_version = "1.6.0+"
  aws_provider_version = "5.30.0+"
  
  # Feature availability flags based on provider versions
  features = {
    # AWS provider features
    aws_s3_bucket_versioning_resource = true  # Available in AWS provider 4.0+
    aws_cloudwatch_event_rule_tags    = true  # Available in AWS provider 4.0+
    aws_lambda_function_architectures  = true  # Available in AWS provider 4.0+
    
    # Terraform features
    terraform_validation_blocks = true  # Available in Terraform 0.13+
    terraform_sensitive_outputs = true  # Available in Terraform 0.14+
    terraform_moved_blocks      = true  # Available in Terraform 1.1+
  }
}

#==============================================================================
# VERSION COMPATIBILITY NOTES
#==============================================================================

# AWS Provider Version History and Feature Support:
# - 5.30.0: Latest features for Bedrock AgentCore (preview services)
# - 5.0.0:  Major version with breaking changes, enhanced resource management
# - 4.0.0:  Introduction of separate resources for S3 bucket configuration
# - 3.74.0: Support for CloudWatch Evidently and other new services

# Terraform Version History and Feature Support:
# - 1.6.0: Enhanced provider development, improved state management
# - 1.5.0: Configuration-driven import, enhanced validation
# - 1.4.0: Terraform Cloud integration improvements
# - 1.3.0: Optional object type attributes, moved blocks
# - 1.2.0: Provider-defined functions, improved error messages
# - 1.1.0: Moved blocks for refactoring, enhanced console UI

# Provider Upgrade Path:
# When upgrading providers, always:
# 1. Review the provider changelog for breaking changes
# 2. Test in a non-production environment first
# 3. Update version constraints gradually
# 4. Run terraform plan to identify potential issues
# 5. Update resource configurations for deprecated features

#==============================================================================
# PROVIDER DEPENDENCY RESOLUTION
#==============================================================================

# The terraform_remote_state data source can be used to reference
# outputs from other Terraform configurations (useful for modular deployments)

# Example for referencing shared infrastructure:
# data "terraform_remote_state" "network" {
#   backend = "s3"
#   config = {
#     bucket = "your-shared-terraform-state-bucket"
#     key    = "network/terraform.tfstate"
#     region = var.aws_region
#   }
# }

# Example for referencing shared security infrastructure:
# data "terraform_remote_state" "security" {
#   backend = "s3"
#   config = {
#     bucket = "your-shared-terraform-state-bucket"
#     key    = "security/terraform.tfstate"
#     region = var.aws_region
#   }
# }