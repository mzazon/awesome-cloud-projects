# Amazon Q Developer Terraform Provider Requirements and Versions
# This file defines the required Terraform version and provider configurations

terraform {
  # Specify the minimum Terraform version required
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # AWS Provider for Amazon Q Developer and IAM resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }

    # Local provider for generating local files and setup instructions
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }

    # Template provider for processing configuration templates
    template = {
      source  = "hashicorp/template"
      version = "~> 2.0"
    }
  }

  # Configure backend for storing Terraform state
  # Uncomment and modify the backend configuration as needed for your environment
  
  # Example: S3 backend configuration
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "amazon-q-developer/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }

  # Example: Local backend configuration (default)
  # backend "local" {
  #   path = "terraform.tfstate"
  # }

  # Example: Terraform Cloud backend configuration
  # cloud {
  #   organization = "your-terraform-organization"
  #   workspaces {
  #     name = "amazon-q-developer"
  #   }
  # }
}

# Configure the AWS Provider with default settings
provider "aws" {
  region = var.aws_region

  # Default tags applied to all AWS resources
  default_tags {
    tags = {
      Project         = "Amazon Q Developer"
      Environment     = var.environment
      ManagedBy       = "Terraform"
      Repository      = "recipes/aws/ai-code-assistant-amazon-q-developer"
      TerraformModule = "amazon-q-developer"
      CreatedDate     = formatdate("YYYY-MM-DD", timestamp())
      LastModified    = formatdate("YYYY-MM-DD'T'hh:mm:ssZ", timestamp())
    }
  }

  # Additional provider configuration options
  # Uncomment and modify as needed for your environment

  # profile = "default"  # AWS CLI profile to use
  # shared_credentials_files = ["~/.aws/credentials"]
  # shared_config_files = ["~/.aws/config"]

  # Custom endpoints for testing or special AWS configurations
  # endpoints {
  #   iam = "https://iam.amazonaws.com"
  #   sts = "https://sts.amazonaws.com"
  #   s3  = "https://s3.amazonaws.com"
  # }

  # Skip region validation for testing purposes
  # skip_region_validation = false

  # Skip credentials validation for testing purposes
  # skip_credentials_validation = false

  # Skip requesting the account ID for testing purposes
  # skip_requesting_account_id = false

  # Custom CA bundle for corporate environments
  # custom_ca_bundle = file("path/to/ca-bundle.pem")

  # Assume role configuration for cross-account access
  # assume_role {
  #   role_arn         = "arn:aws:iam::123456789012:role/TerraformRole"
  #   session_name     = "terraform-amazon-q-developer"
  #   external_id      = "unique-external-id"
  #   duration_seconds = 3600
  # }

  # Forbidden account IDs to prevent accidental deployment
  # forbidden_account_ids = ["123456789012"]

  # Allowed account IDs to restrict deployment to specific accounts
  # allowed_account_ids = ["123456789012", "210987654321"]

  # Ignore specific tags during resource lifecycle management
  # ignore_tags {
  #   keys         = ["LastModified", "CreatedDate"]
  #   key_prefixes = ["Environment"]
  # }

  # HTTP retry configuration
  # retry_mode = "standard"
  # max_retries = 3

  # S3 specific configuration
  # s3_use_path_style = false
  # s3_force_path_style = false
}

# Configure the Random Provider
provider "random" {
  # Random provider typically doesn't require configuration
  # All settings are handled at the resource level
}

# Configure the Local Provider
provider "local" {
  # Local provider typically doesn't require configuration
  # All settings are handled at the resource level
}

# Configure the Template Provider
provider "template" {
  # Template provider typically doesn't require configuration
  # All settings are handled at the resource level
}

# Version constraints for compatibility
# These comments document the version compatibility matrix

# Terraform Core Compatibility:
# - Terraform >= 1.0.0: Full feature support
# - Terraform >= 0.15.0: Limited support (some features may not work)
# - Terraform < 0.15.0: Not supported

# AWS Provider Compatibility:
# - AWS Provider 5.x: Full feature support, latest AWS services
# - AWS Provider 4.x: Limited support, some newer services unavailable
# - AWS Provider < 4.x: Not recommended, security vulnerabilities

# Amazon Q Developer Service Availability:
# - Amazon Q Developer is available in most AWS regions
# - Check AWS documentation for region-specific availability
# - Some features may have regional limitations

# IAM Identity Center Requirements:
# - Requires IAM Identity Center to be enabled in the AWS account
# - IAM Identity Center instance must be configured before deployment
# - Cross-region IAM Identity Center access may have limitations

# Known Compatibility Issues:
# - Some AWS services may not be available in all regions
# - IAM eventual consistency may cause temporary resource creation delays
# - S3 bucket names must be globally unique across all AWS accounts

# Upgrade Path:
# - Always test Terraform upgrades in a development environment first
# - Review AWS provider changelog for breaking changes
# - Update required_version constraints gradually
# - Monitor AWS service deprecation announcements

# Security Considerations:
# - Always use the latest stable provider versions for security patches
# - Regularly review and update version constraints
# - Monitor security advisories for Terraform and AWS providers
# - Use state file encryption and access controls

# Performance Considerations:
# - Newer provider versions typically include performance improvements
# - Some resources may have better state refresh performance
# - Parallel resource creation limits may vary by provider version
# - API rate limiting behavior may change between versions