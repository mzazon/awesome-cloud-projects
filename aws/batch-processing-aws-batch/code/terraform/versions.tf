# ======================================================================
# AWS Batch Processing Workloads - Terraform Version Requirements
#
# This file defines the Terraform version and provider requirements
# for the AWS Batch infrastructure deployment. It follows current
# best practices for version constraints and provider configuration.
# ======================================================================

# Terraform version and required providers
terraform {
  required_version = ">= 1.6"

  required_providers {
    # AWS Provider - Using version 5.x for latest features and security updates
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    
    # Random Provider - For generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Optional: Remote state backend configuration
  # Uncomment and configure for production deployments
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "batch-processing/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  #   
  #   # Optional: KMS key for state encryption
  #   # kms_key_id = "alias/terraform-state-key"
  # }
}

# ======================================================================
# AWS PROVIDER CONFIGURATION
# ======================================================================

# Configure the AWS Provider with default tags and security settings
provider "aws" {
  # Default tags applied to all resources created by this provider
  default_tags {
    tags = {
      Project              = "AWS Batch Processing Workloads"
      Environment          = var.environment
      ManagedBy           = "Terraform"
      Recipe              = "batch-processing-workloads-aws-batch"
      TerraformVersion    = "~> 1.6"
      AWSProviderVersion  = "~> 5.70"
      CreatedDate         = formatdate("YYYY-MM-DD", timestamp())
    }
  }

  # Optional: Assume role configuration for cross-account deployments
  # Uncomment and configure if deploying to a different AWS account
  #
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT_ID:role/TerraformDeploymentRole"
  #   session_name = "terraform-batch-deployment"
  # }

  # Optional: Shared configuration and credentials file paths
  # Uncomment if using custom AWS configuration paths
  #
  # shared_config_files      = ["/path/to/config"]
  # shared_credentials_files = ["/path/to/credentials"]
  # profile                  = "your-aws-profile"

  # Security: Require HTTPS for all AWS API calls
  # This ensures all communication with AWS services is encrypted
  skip_metadata_api_check     = false
  skip_region_validation      = false
  skip_credentials_validation = false

  # Retry configuration for handling temporary API failures
  retry_mode      = "adaptive"
  max_retries     = 3
}

# ======================================================================
# RANDOM PROVIDER CONFIGURATION
# ======================================================================

# Configure the Random Provider
# No specific configuration required, using defaults