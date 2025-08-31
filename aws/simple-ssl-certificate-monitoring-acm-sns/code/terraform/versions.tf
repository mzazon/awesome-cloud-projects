# ==============================================================================
# Terraform and Provider Version Requirements
# ==============================================================================
# This file specifies the required versions of Terraform and providers
# to ensure compatibility and access to required features.
# ==============================================================================

terraform {
  # Require Terraform version 1.0 or later for full feature compatibility
  required_version = ">= 1.0"

  # Provider requirements with version constraints
  required_providers {
    # AWS Provider - Primary provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Use AWS provider v5.x for latest features and security updates
    }
    
    # Random Provider - Used for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"  # Stable version for random ID generation
    }
  }

  # Optional: Backend configuration for state management
  # Uncomment and configure based on your requirements
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "ssl-certificate-monitoring/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# ==============================================================================
# AWS Provider Configuration
# ==============================================================================

provider "aws" {
  # AWS provider configuration
  # The provider will use credentials from:
  # 1. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
  # 2. AWS credentials file (~/.aws/credentials)
  # 3. IAM roles for EC2 instances or ECS tasks
  # 4. AWS SSO profiles
  
  # Optional: Specify default region if not set in environment
  # region = "us-west-2"
  
  # Optional: Add default tags to all resources
  default_tags {
    tags = {
      Terraform   = "true"
      Project     = "SSL Certificate Monitoring"
      Repository  = "recipes/aws/simple-ssl-certificate-monitoring-acm-sns"
      ManagedBy   = "Terraform"
    }
  }
}

# ==============================================================================
# Random Provider Configuration
# ==============================================================================

provider "random" {
  # Random provider configuration
  # No specific configuration required for basic usage
}