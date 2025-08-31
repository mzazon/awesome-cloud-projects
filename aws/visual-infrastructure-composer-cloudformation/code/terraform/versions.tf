# =============================================================================
# Terraform and Provider Version Requirements
# =============================================================================
# This file defines the minimum required versions for Terraform and providers
# to ensure compatibility and access to required features.

terraform {
  # Minimum Terraform version required
  # Version 1.5.0+ is recommended for the latest features and stability
  required_version = ">= 1.5.0"

  # Required providers and their version constraints
  required_providers {
    # AWS Provider - Official provider for Amazon Web Services
    # Version 5.0+ includes the latest S3 features and security improvements
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider - Used for generating unique resource names
    # Version 3.1+ provides stable random string generation
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Optional: Configure backend for state storage
  # Uncomment and configure the backend block below for production deployments
  # 
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "visual-infrastructure-composer/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  # }
  #
  # Alternative backend options:
  #
  # backend "remote" {
  #   organization = "your-terraform-cloud-org"
  #   workspaces {
  #     name = "visual-infrastructure-composer"
  #   }
  # }
}

# =============================================================================
# Provider Configuration
# =============================================================================

# Configure the AWS Provider
# The provider will use credentials from the environment or AWS CLI configuration
provider "aws" {
  # Optional: Set the region explicitly
  # region = var.aws_region

  # Default tags to apply to all resources managed by this provider
  default_tags {
    tags = {
      TerraformManaged = "true"
      Project         = "visual-infrastructure-composer"
      Repository      = "recipes"
      Recipe          = "visual-infrastructure-composer-cloudformation"
    }
  }
}

# Configure the Random Provider
# This provider is used to generate unique suffixes for resource naming
provider "random" {
  # No additional configuration needed for the random provider
}