# =============================================================================
# TERRAFORM AND PROVIDER VERSIONS - AUTOMATED SECURITY SCANNING
# =============================================================================
# This file defines the required Terraform version and provider versions
# for the automated security scanning solution with Inspector and Security Hub.
# Version constraints ensure compatibility and stability.
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider for main infrastructure resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Archive provider for Lambda function packaging
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# =============================================================================
# PROVIDER CONFIGURATIONS
# =============================================================================

# Configure the AWS Provider with default tags and region settings
provider "aws" {
  # Default tags applied to all resources created by this provider
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = "AutomatedSecurityScanning"
      Repository  = "recipes/aws/automated-security-scanning-inspector-security-hub"
      Component   = "SecurityInfrastructure"
    }
  }

  # Skip metadata API check for faster provider initialization in CI/CD
  skip_metadata_api_check     = false
  skip_region_validation     = false
  skip_credentials_validation = false
  skip_requesting_account_id = false
}

# Configure the Archive provider for Lambda function packaging
provider "archive" {
  # No additional configuration required
}

# Configure the Random provider for unique identifier generation
provider "random" {
  # No additional configuration required
}

# =============================================================================
# TERRAFORM BACKEND CONFIGURATION (OPTIONAL)
# =============================================================================
# Uncomment and configure the backend block below for remote state management.
# This is recommended for production deployments to enable state locking,
# versioning, and team collaboration.

/*
terraform {
  backend "s3" {
    # Replace with your actual S3 bucket name
    bucket = "your-terraform-state-bucket"
    
    # Key path for this specific module's state
    key = "security/automated-security-scanning/terraform.tfstate"
    
    # AWS region where the S3 bucket is located
    region = "us-east-1"
    
    # DynamoDB table for state locking (recommended)
    dynamodb_table = "terraform-state-locks"
    
    # Enable state encryption at rest
    encrypt = true
    
    # Prevent accidental deletion of state file
    versioning = true
  }
}
*/

# =============================================================================
# PROVIDER VERSION EXPLANATIONS
# =============================================================================

# AWS Provider ~> 5.0
# -------------------
# - Provides comprehensive coverage of AWS services including Security Hub, Inspector V2, EventBridge
# - Version 5.x includes native support for Inspector V2 resources
# - Contains latest Security Hub features and compliance standards
# - Includes improved EventBridge rule and target configurations
# - Supports advanced IAM policy features and conditions

# Archive Provider ~> 2.0
# ------------------------
# - Used for creating ZIP archives of Lambda function source code
# - Version 2.x provides improved handling of file permissions and timestamps
# - Essential for packaging Python Lambda functions with dependencies
# - Supports both file-based and content-based archive creation

# Random Provider ~> 3.0
# -----------------------
# - Generates cryptographically secure random values for resource naming
# - Used to ensure S3 bucket names are globally unique
# - Version 3.x includes improved entropy and security features
# - Provides consistent random value generation across Terraform runs

# =============================================================================
# COMPATIBILITY AND UPGRADE NOTES
# =============================================================================

# Terraform Version Compatibility:
# - Minimum version 1.0 required for stable language features
# - Compatible with Terraform 1.0.x through 1.6.x
# - Uses modern Terraform syntax including optional object attributes
# - Leverages improved variable validation and sensitive value handling

# AWS Provider Upgrade Path:
# - If upgrading from AWS provider 4.x, review breaking changes
# - Inspector V2 resources may require state migration from V1
# - EventBridge resources have improved validation in 5.x
# - Security Hub insight configurations may need adjustment

# Breaking Changes from Previous Versions:
# - Inspector V1 resources are deprecated in favor of V2
# - Some EventBridge target configurations have changed
# - IAM policy document structure improvements require review

# =============================================================================
# EXPERIMENTAL FEATURES (IF ANY)
# =============================================================================

# Currently, this configuration does not use any experimental Terraform features.
# If experimental features are needed in the future, they should be documented here
# with clear migration paths and stability considerations.

# =============================================================================
# PROVIDER AUTHENTICATION
# =============================================================================

# This configuration supports multiple AWS authentication methods:
# 1. AWS CLI profile: aws configure set profile <profile-name>
# 2. Environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION
# 3. IAM roles: When running on EC2 instances or in AWS services
# 4. AWS SSO: When configured with aws sso login

# For production deployments, consider using:
# - IAM roles for cross-account access
# - AWS SSO for user-based access
# - Service-linked roles for AWS service integrations
# - Least privilege IAM policies for Terraform execution