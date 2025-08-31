# ================================================================================
# Provider Requirements and Version Constraints
# ================================================================================
# This file defines the required Terraform version and provider versions
# for the enterprise identity federation infrastructure.

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider for core AWS services
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive provider for creating Lambda function deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }

    # Template provider for processing configuration templates
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }
}

# ================================================================================
# AWS Provider Configuration
# ================================================================================

provider "aws" {
  # Provider configuration is inherited from environment variables or AWS CLI configuration
  # The following tags will be applied to all resources that support tags
  default_tags {
    tags = {
      Terraform   = "true"
      Project     = "BedrockAgentCore"
      Recipe      = "enterprise-identity-federation-bedrock-agentcore"
      Repository  = "recipes"
      ManagedBy   = "Terraform"
    }
  }
}

# ================================================================================
# Provider Version Requirements Explanation
# ================================================================================

# AWS Provider v5.x: 
# - Provides latest AWS service support including Bedrock and enhanced Cognito features
# - Includes improved resource management and state handling
# - Supports advanced security features and compliance controls
# - Compatible with latest AWS API versions

# Random Provider v3.x:
# - Provides cryptographically secure random value generation
# - Used for creating unique resource identifiers and suffixes
# - Ensures resource name uniqueness across deployments

# Archive Provider v2.x:
# - Creates ZIP archives for Lambda function deployment
# - Supports file content templating and dynamic archive creation
# - Integrates with Terraform lifecycle management

# Template Provider v2.x:
# - Processes configuration templates with variable substitution
# - Used for Lambda function code generation with dynamic content
# - Supports complex templating scenarios for enterprise configurations

# ================================================================================
# Backend Configuration (Optional)
# ================================================================================

# Uncomment and configure the backend block below to use remote state storage
# This is recommended for production deployments to enable team collaboration
# and state locking.

# terraform {
#   backend "s3" {
#     # S3 bucket for storing Terraform state
#     bucket = "your-terraform-state-bucket"
#     key    = "enterprise-identity-federation/terraform.tfstate"
#     region = "us-east-1"
#     
#     # DynamoDB table for state locking
#     dynamodb_table = "terraform-state-locks"
#     encrypt        = true
#     
#     # Optional: KMS key for state encryption
#     # kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
#   }
# }

# Alternative backend configurations:

# Terraform Cloud/Enterprise:
# terraform {
#   cloud {
#     organization = "your-organization"
#     workspaces {
#       name = "enterprise-identity-federation"
#     }
#   }
# }

# Azure Storage Account:
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "tfstate-rg"
#     storage_account_name = "tfstateaccount"
#     container_name       = "tfstate"
#     key                  = "enterprise-identity-federation.terraform.tfstate"
#   }
# }

# Google Cloud Storage:
# terraform {
#   backend "gcs" {
#     bucket = "your-terraform-state-bucket"
#     prefix = "enterprise-identity-federation"
#   }
# }

# ================================================================================
# Experimental Features (Optional)
# ================================================================================

# Uncomment to enable experimental Terraform features if needed
# terraform {
#   experiments = [module_variable_optional_attrs]
# }

# ================================================================================
# Version Compatibility Notes
# ================================================================================

# This configuration is tested and compatible with:
# - Terraform CLI version 1.0 and above
# - AWS Provider version 5.0 and above
# - AWS CLI version 2.0 and above
# - Python 3.8 and above (for Lambda functions)

# Minimum AWS Service API versions supported:
# - Amazon Cognito Identity Provider: 2016-04-18
# - AWS Lambda: 2015-03-31
# - Amazon S3: 2006-03-01
# - AWS IAM: 2010-05-08
# - AWS CloudTrail: 2013-11-01
# - Amazon CloudWatch: 2010-08-01
# - AWS Systems Manager: 2014-11-06

# For the latest compatibility information, refer to:
# - Terraform AWS Provider documentation: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
# - AWS Service API documentation: https://docs.aws.amazon.com/
# - Terraform version compatibility: https://www.terraform.io/docs/language/settings/index.html